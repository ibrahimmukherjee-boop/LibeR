#ifndef LIBERTAD_EIGEN_SOLVER_HPP
#define LIBERTAD_EIGEN_SOLVER_HPP

#include <LibeRtAD/eigen.hpp>

#if defined(__GNUC__) && !defined(__clang__)
// Eigen upstream issue #2304: GCC can report a false positive while
// instantiating the self-adjoint solver.
#define LIBERTAD_EIGEN_SOLVER_DIAGNOSTIC(x) _Pragma(#x)
LIBERTAD_EIGEN_SOLVER_DIAGNOSTIC(GCC diagnostic push)
LIBERTAD_EIGEN_SOLVER_DIAGNOSTIC(
    GCC diagnostic ignored "-Wmaybe-uninitialized")
#endif

namespace libertad {
namespace detail {

struct SelfAdjointEigenResult {
  Eigen::ComputationInfo info = Eigen::InvalidInput;
  Eigen::VectorXd values;
  Eigen::MatrixXd vectors;
};

inline SelfAdjointEigenResult self_adjoint_eigen(
    const Eigen::MatrixXd& matrix, bool compute_vectors = true) {
  Eigen::SelfAdjointEigenSolver<Eigen::MatrixXd> solver;
  solver.compute(
      matrix,
      compute_vectors ? Eigen::ComputeEigenvectors : Eigen::EigenvaluesOnly);
  SelfAdjointEigenResult output{};
  output.info = solver.info();
  if (output.info == Eigen::Success) {
    output.values = solver.eigenvalues();
    if (compute_vectors) output.vectors = solver.eigenvectors();
  }
  return output;
}

}  // namespace detail
}  // namespace libertad

#if defined(__GNUC__) && !defined(__clang__)
LIBERTAD_EIGEN_SOLVER_DIAGNOSTIC(GCC diagnostic pop)
#undef LIBERTAD_EIGEN_SOLVER_DIAGNOSTIC
#endif

#endif
