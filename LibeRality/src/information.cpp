#if defined(__GNUC__) && !defined(__clang__)
// Eigen tracks this optimizer false positive as upstream issue #2304 and
// suppresses it for GCC in its own test builds.
#define LIBERALITY_GCC_DIAGNOSTIC(x) _Pragma(#x)
LIBERALITY_GCC_DIAGNOSTIC(GCC diagnostic ignored "-Wmaybe-uninitialized")
#endif

#include <Rcpp.h>
#include <LibeRtAD/eigen_r.hpp>

// [[Rcpp::depends(LibeRtAD)]]
// [[Rcpp::plugins(cpp17)]]

namespace {

Eigen::MatrixXd symmetric_inverse(const Eigen::MatrixXd& input,
                                  double tolerance,
                                  int* rank = nullptr,
                                  Eigen::VectorXd* eigenvalues = nullptr) {
  if (input.rows() != input.cols()) Rcpp::stop("Matrix must be square.");
  if (!input.allFinite()) Rcpp::stop("Matrix contains non-finite values.");
  const Eigen::MatrixXd symmetric = 0.5 * (input + input.transpose());
  Eigen::SelfAdjointEigenSolver<Eigen::MatrixXd> solver(symmetric);
  if (solver.info() != Eigen::Success) Rcpp::stop("Symmetric eigendecomposition failed.");
  const Eigen::VectorXd values = solver.eigenvalues();
  const double scale = std::max(1.0, values.cwiseAbs().maxCoeff());
  const double threshold = tolerance * scale;
  Eigen::VectorXd inverse_values(values.size());
  int numerical_rank = 0;
  for (Eigen::Index i = 0; i < values.size(); ++i) {
    if (values[i] > threshold) {
      inverse_values[i] = 1.0 / values[i];
      ++numerical_rank;
    } else {
      inverse_values[i] = 0.0;
    }
  }
  if (rank) *rank = numerical_rank;
  if (eigenvalues) *eigenvalues = values.reverse();
  return solver.eigenvectors() * inverse_values.asDiagonal() * solver.eigenvectors().transpose();
}

} // namespace

#if defined(__GNUC__) && !defined(__clang__)
#undef LIBERALITY_GCC_DIAGNOSTIC
#endif

// Assemble the expected information for a multivariate normal working model.
// Dmu has one column per estimated parameter. dV contains the corresponding
// covariance derivatives. This covers mean, covariance, and cross information.
// [[Rcpp::export]]
Rcpp::List lity_fim_cpp(const Rcpp::NumericMatrix& Dmu_input,
                        const Rcpp::NumericMatrix& V_input,
                        const Rcpp::List& dV,
                        double tolerance = 1e-10) {
  const Eigen::MatrixXd Dmu = libertad::r_matrix_map(Dmu_input);
  const Eigen::MatrixXd V = libertad::r_matrix_map(V_input);
  if (V.rows() != V.cols() || V.rows() != Dmu.rows()) {
    Rcpp::stop("Dmu and V dimensions are incompatible.");
  }
  const int parameters = static_cast<int>(Dmu.cols());
  if (dV.size() != parameters) Rcpp::stop("dV must contain one matrix per parameter.");
  int covariance_rank = 0;
  Eigen::VectorXd covariance_eigenvalues;
  const Eigen::MatrixXd inverse = symmetric_inverse(V, tolerance, &covariance_rank,
                                                     &covariance_eigenvalues);
  Eigen::MatrixXd information = Dmu.transpose() * inverse * Dmu;
  std::vector<Eigen::MatrixXd> products;
  products.reserve(static_cast<std::size_t>(parameters));
  for (int i = 0; i < parameters; ++i) {
    Rcpp::NumericMatrix derivative_input(dV[i]);
    Eigen::MatrixXd derivative = libertad::r_matrix_map(derivative_input);
    if (derivative.rows() != V.rows() || derivative.cols() != V.cols()) {
      Rcpp::stop("A covariance derivative has incompatible dimensions.");
    }
    products.push_back(inverse * derivative);
  }
  for (int i = 0; i < parameters; ++i) {
    for (int j = i; j < parameters; ++j) {
      const double covariance_information =
        0.5 * (products[static_cast<std::size_t>(i)] *
               products[static_cast<std::size_t>(j)]).trace();
      information(i, j) += covariance_information;
      if (i != j) information(j, i) += covariance_information;
    }
  }
  information = 0.5 * (information + information.transpose());
  return Rcpp::List::create(
    Rcpp::Named("information") = libertad::eigen_matrix_to_r(information),
    Rcpp::Named("inverse_observation_covariance") = libertad::eigen_matrix_to_r(inverse),
    Rcpp::Named("observation_covariance_rank") = covariance_rank,
    Rcpp::Named("observation_covariance_eigenvalues") =
      libertad::eigen_vector_to_r(covariance_eigenvalues)
  );
}

// [[Rcpp::export]]
Rcpp::List lity_matrix_metrics_cpp(const Rcpp::NumericMatrix& information_input,
                                   double tolerance = 1e-10) {
  const Eigen::MatrixXd information = libertad::r_matrix_map(information_input);
  if (information.rows() != information.cols()) Rcpp::stop("Information matrix must be square.");
  int rank = 0;
  Eigen::VectorXd eigenvalues;
  const Eigen::MatrixXd covariance = symmetric_inverse(information, tolerance, &rank, &eigenvalues);
  const double scale = eigenvalues.size() ? std::max(1.0, eigenvalues.cwiseAbs().maxCoeff()) : 1.0;
  const double threshold = tolerance * scale;
  double log_determinant = 0.0;
  double minimum_positive = R_PosInf;
  double maximum = 0.0;
  for (Eigen::Index i = 0; i < eigenvalues.size(); ++i) {
    maximum = std::max(maximum, eigenvalues[i]);
    if (eigenvalues[i] > threshold) {
      log_determinant += std::log(eigenvalues[i]);
      minimum_positive = std::min(minimum_positive, eigenvalues[i]);
    }
  }
  if (rank < information.rows()) log_determinant = R_NegInf;
  const double condition = (rank > 0 && R_finite(minimum_positive)) ? maximum / minimum_positive : R_PosInf;
  return Rcpp::List::create(
    Rcpp::Named("covariance") = libertad::eigen_matrix_to_r(covariance),
    Rcpp::Named("eigenvalues") = libertad::eigen_vector_to_r(eigenvalues),
    Rcpp::Named("rank") = rank,
    Rcpp::Named("condition_number") = condition,
    Rcpp::Named("log_determinant") = log_determinant,
    Rcpp::Named("trace_covariance") = covariance.trace(),
    Rcpp::Named("minimum_eigenvalue") = eigenvalues.size() ? eigenvalues.minCoeff() : R_NegInf
  );
}

// Accumulate many endpoint/stratum/arm information blocks in one native pass
// and calculate matrix diagnostics without materialising an intermediate R
// matrix after every addition.
// [[Rcpp::export]]
Rcpp::List lity_weighted_information_cpp(
    const Rcpp::List& matrices, const Rcpp::NumericVector& weights,
    const Rcpp::Nullable<Rcpp::NumericMatrix>& prior_input = R_NilValue,
    double tolerance = 1e-10) {
  if (matrices.size() != weights.size()) {
    Rcpp::stop("Information blocks and weights must have equal length.");
  }
  Eigen::MatrixXd total;
  bool initialized = false;
  for (R_xlen_t index = 0; index < matrices.size(); ++index) {
    Rcpp::NumericMatrix source(matrices[index]);
    const Eigen::MatrixXd block = libertad::r_matrix_map(source);
    if (block.rows() != block.cols()) {
      Rcpp::stop("Every information block must be square.");
    }
    if (!initialized) {
      total = Eigen::MatrixXd::Zero(block.rows(), block.cols());
      initialized = true;
    } else if (block.rows() != total.rows()) {
      Rcpp::stop("Information block dimensions do not match.");
    }
    if (!std::isfinite(weights[index]) || weights[index] < 0.0) {
      Rcpp::stop("Information weights must be finite and non-negative.");
    }
    total.noalias() += weights[index] * block;
  }
  if (prior_input.isNotNull()) {
    Rcpp::NumericMatrix source(prior_input);
    const Eigen::MatrixXd prior = libertad::r_matrix_map(source);
    if (!initialized) {
      total = prior;
      initialized = true;
    } else if (prior.rows() != total.rows() || prior.cols() != total.cols()) {
      Rcpp::stop("Prior information dimensions do not match.");
    } else {
      total += prior;
    }
  }
  if (!initialized) Rcpp::stop("At least one information block or prior is required.");
  total = 0.5 * (total + total.transpose()).eval();
  Rcpp::NumericMatrix wrapped = libertad::eigen_matrix_to_r(total);
  Rcpp::List metrics = lity_matrix_metrics_cpp(wrapped, tolerance);
  metrics["information"] = wrapped;
  metrics["blocks"] = matrices.size();
  return metrics;
}
