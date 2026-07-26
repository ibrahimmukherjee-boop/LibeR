// [[Rcpp::plugins(cpp17)]]

#include <Rcpp.h>
#include <LibeRtAD/eigen.hpp>
#include <LibeRtAD/program.hpp>
#include <LibeRtAD/eigen_solver.hpp>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <limits>
#include <functional>
#include <map>
#include <sstream>
#include <string>
#include <unordered_set>
#include <utility>
#include <vector>

namespace {

using libertad::Program;
using libertad::ProgramHandle;
using libertad::TapeHandle;

std::vector<std::string> character_vector(const Rcpp::CharacterVector& x) {
  return Rcpp::as<std::vector<std::string>>(x);
}

std::vector<double> numeric_vector(const Rcpp::NumericVector& x) {
  return Rcpp::as<std::vector<double>>(x);
}

void ensure_unique(const std::vector<std::string>& values, const char* what) {
  std::unordered_set<std::string> seen;
  for (const std::string& value : values) {
    if (!seen.insert(value).second) {
      Rcpp::stop("Duplicate %s name: %s", what, value.c_str());
    }
  }
}

Rcpp::NumericVector named_vector(const std::vector<double>& values,
                                 const std::vector<std::string>& names) {
  Rcpp::NumericVector result(values.begin(), values.end());
  result.attr("names") = Rcpp::wrap(names);
  return result;
}

std::vector<double> tape_point(const TapeHandle& tape, const Rcpp::NumericVector& x) {
  if (x.size() != static_cast<R_xlen_t>(tape.domain.size())) {
    Rcpp::stop("Tape point has length %lld; expected %lld.",
               static_cast<long long>(x.size()),
               static_cast<long long>(tape.domain.size()));
  }
  return numeric_vector(x);
}

std::vector<double> tape_forward_zero(TapeHandle& tape,
                                      const std::vector<double>& point) {
  std::ostringstream messages;
  return tape.fun.Forward(0, point, messages);
}

void tape_new_dynamic(TapeHandle& tape, const std::vector<double>& values) {
  if (values.size() != tape.dynamic.size()) {
    Rcpp::stop("Dynamic parameter vector has length %lld; expected %lld.",
               static_cast<long long>(values.size()),
               static_cast<long long>(tape.dynamic.size()));
  }
  tape.fun.new_dynamic(values);
  tape.dynamic_values = values;
}

std::vector<double> tape_jacobian(TapeHandle& tape,
                                  const std::vector<double>& point) {
  const std::size_t n = tape.domain.size();
  const std::size_t m = tape.range.size();
  std::vector<double> jacobian(m * n, 0.0);
  if (m * n >= 4096U && m >= 32U) {
    CppAD::vectorBool select_domain(n), select_range(m);
    for (std::size_t j = 0; j < n; ++j) select_domain[j] = true;
    for (std::size_t i = 0; i < m; ++i) select_range[i] = true;
    using SizeVector = CppAD::vector<std::size_t>;
    using BaseVector = CppAD::vector<double>;
    CppAD::sparse_rcv<SizeVector, BaseVector> sparse;
    BaseVector x(point.size());
    for (std::size_t j = 0; j < point.size(); ++j) x[j] = point[j];
    tape.fun.subgraph_jac_rev(select_domain, select_range, x, sparse);
    for (std::size_t k = 0; k < sparse.nnz(); ++k) {
      jacobian[sparse.row()[k] * n + sparse.col()[k]] = sparse.val()[k];
    }
    tape.derivative_strategy = "subgraph-reverse";
    tape.jacobian_nonzeros = sparse.nnz();
    return jacobian;
  }
  tape_forward_zero(tape, point);
  if (n <= m) {
    constexpr std::size_t block_max = 16U;
    for (std::size_t first = 0; first < n; first += block_max) {
      const std::size_t directions = std::min(block_max, n - first);
      std::vector<double> seed(n * directions, 0.0);
      for (std::size_t direction = 0; direction < directions; ++direction) {
        seed[(first + direction) * directions + direction] = 1.0;
      }
      const std::vector<double> derivative = directions == 1U ?
        tape.fun.Forward(1, seed) :
        tape.fun.Forward(1, directions, seed);
      for (std::size_t i = 0; i < m; ++i) {
        for (std::size_t direction = 0; direction < directions; ++direction) {
          jacobian[i * n + first + direction] =
            derivative[i * directions + direction];
        }
      }
    }
    tape.derivative_strategy = n == 1U ? "forward" : "multi-forward";
  } else {
    std::vector<double> weight(m, 0.0);
    for (std::size_t i = 0; i < m; ++i) {
      weight[i] = 1.0;
      std::vector<double> derivative = tape.fun.Reverse(1, weight);
      weight[i] = 0.0;
      for (std::size_t j = 0; j < n; ++j) jacobian[i * n + j] = derivative[j];
    }
    tape.derivative_strategy = "reverse";
  }
  tape.jacobian_nonzeros = static_cast<std::size_t>(std::count_if(
    jacobian.begin(), jacobian.end(), [](double value) { return value != 0.0; }));
  return jacobian;
}

std::vector<double> tape_hessian(TapeHandle& tape,
                                 const std::vector<double>& point) {
  const std::size_t n = tape.domain.size();
  libertad::analyse_hessian_sparsity(tape.fun, tape.hessian_cache);
  if (tape.hessian_cache.use_sparse) {
    return libertad::sparse_hessian(tape.fun, point, tape.hessian_cache);
  }
  tape_forward_zero(tape, point);
  std::vector<double> hessian(n * n, 0.0);
  std::vector<double> direction(n, 0.0);
  std::vector<double> weight(1, 1.0);
  std::ostringstream messages;
  for (std::size_t j = 0; j < n; ++j) {
    direction[j] = 1.0;
    tape.fun.Forward(1, direction, messages);
    direction[j] = 0.0;
    std::vector<double> reverse = tape.fun.Reverse(2, weight);
    for (std::size_t k = 0; k < n; ++k) hessian[k * n + j] = reverse[k * 2 + 1];
  }
  return hessian;
}

}  // namespace

// [[Rcpp::export(name = ".libertad_program_create")]]
SEXP libertad_program_create(const Rcpp::List& ir) {
  Rcpp::XPtr<ProgramHandle> pointer(new ProgramHandle(ir), true);
  pointer.attr("class") = Rcpp::CharacterVector::create("libertad_program_ptr", "externalptr");
  return pointer;
}

// [[Rcpp::export(name = ".libertad_program_value")]]
Rcpp::NumericVector libertad_program_value(
    SEXP program_pointer,
    const Rcpp::NumericVector& at,
    const Rcpp::CharacterVector& outputs) {
  Rcpp::XPtr<ProgramHandle> handle(program_pointer);
  std::vector<std::string> output_names = character_vector(outputs);
  std::vector<std::size_t> selected = handle->program->select_outputs(output_names);
  std::vector<double> values = handle->program->eval_outputs(numeric_vector(at), selected);
  return named_vector(values, output_names);
}

// [[Rcpp::export(name = ".libertad_tape_create")]]
SEXP libertad_tape_create(
    SEXP program_pointer,
    const Rcpp::NumericVector& at,
    const Rcpp::CharacterVector& wrt,
    const Rcpp::CharacterVector& outputs,
    bool optimize = true) {
  Rcpp::XPtr<ProgramHandle> handle(program_pointer);
  const Program& program = *handle->program;
  std::vector<std::string> domain = character_vector(wrt);
  std::vector<std::string> range = character_vector(outputs);
  if (domain.empty()) Rcpp::stop("A tape requires at least one differentiation input.");
  if (range.empty()) Rcpp::stop("A tape requires at least one output.");
  ensure_unique(domain, "tape input");
  ensure_unique(range, "tape output");
  if (at.size() != static_cast<R_xlen_t>(program.input_names.size())) {
    Rcpp::stop("Recording point has the wrong length.");
  }

  std::vector<int> wrt_positions;
  wrt_positions.reserve(domain.size());
  for (const std::string& name : domain) {
    auto it = program.input_positions.find(name);
    if (it == program.input_positions.end()) {
      Rcpp::stop("Unknown tape input: %s", name.c_str());
    }
    wrt_positions.push_back(static_cast<int>(it->second));
  }
  std::unordered_set<int> active_positions(wrt_positions.begin(), wrt_positions.end());
  std::vector<std::string> dynamic_names;
  std::vector<int> dynamic_positions;
  std::vector<double> dynamic_values;
  dynamic_names.reserve(program.input_names.size() - domain.size());
  dynamic_positions.reserve(program.input_names.size() - domain.size());
  dynamic_values.reserve(program.input_names.size() - domain.size());
  for (std::size_t i = 0; i < program.input_names.size(); ++i) {
    if (active_positions.count(static_cast<int>(i)) == 0U) {
      dynamic_names.push_back(program.input_names[i]);
      dynamic_positions.push_back(static_cast<int>(i));
      dynamic_values.push_back(at[i]);
    }
  }
  std::vector<std::size_t> selected = program.select_outputs(range);

  using AD = CppAD::AD<double>;
  std::vector<AD> independent(domain.size());
  std::vector<AD> dynamic(dynamic_names.size());
  for (std::size_t i = 0; i < domain.size(); ++i) {
    independent[i] = at[wrt_positions[i]];
  }
  for (std::size_t i = 0; i < dynamic.size(); ++i) {
    dynamic[i] = dynamic_values[i];
  }
  CppAD::Independent(independent, dynamic);

  std::vector<AD> full_inputs(program.input_names.size());
  for (std::size_t i = 0; i < domain.size(); ++i) {
    full_inputs[static_cast<std::size_t>(wrt_positions[i])] = independent[i];
  }
  for (std::size_t i = 0; i < dynamic.size(); ++i) {
    full_inputs[static_cast<std::size_t>(dynamic_positions[i])] = dynamic[i];
  }
  std::vector<AD> dependent = program.eval_outputs(full_inputs, selected);
  CppAD::ADFun<double> fun;
  fun.Dependent(independent, dependent);
  if (optimize) fun.optimize();

  Rcpp::XPtr<TapeHandle> pointer(
    new TapeHandle(handle->program, std::move(fun), domain, dynamic_names,
                   dynamic_values, range), true
  );
  pointer.attr("class") = Rcpp::CharacterVector::create("libertad_tape_ptr", "externalptr");
  pointer.attr("domain") = Rcpp::wrap(domain);
  pointer.attr("dynamic") = Rcpp::wrap(dynamic_names);
  pointer.attr("range") = Rcpp::wrap(range);
  return pointer;
}

// [[Rcpp::export(name = ".libertad_tape_new_dynamic")]]
Rcpp::NumericVector libertad_tape_new_dynamic(
    SEXP tape_pointer,
    const Rcpp::NumericVector& values) {
  Rcpp::XPtr<TapeHandle> tape(tape_pointer);
  tape_new_dynamic(*tape, numeric_vector(values));
  return named_vector(tape->dynamic_values, tape->dynamic);
}

// [[Rcpp::export(name = ".libertad_tape_info")]]
Rcpp::List libertad_tape_info(SEXP tape_pointer) {
  Rcpp::XPtr<TapeHandle> tape(tape_pointer);
  const std::size_t taylor_bytes =
    tape->fun.size_var() * tape->fun.size_order() *
    std::max<std::size_t>(tape->fun.size_direction(), 1U) * sizeof(double);
  return Rcpp::List::create(
    Rcpp::Named("domain") = tape->domain,
    Rcpp::Named("dynamic") = tape->dynamic,
    Rcpp::Named("dynamic_values") = named_vector(tape->dynamic_values, tape->dynamic),
    Rcpp::Named("range") = tape->range,
    Rcpp::Named("operations") = static_cast<double>(tape->fun.size_op()),
    Rcpp::Named("operator_arguments") =
      static_cast<double>(tape->fun.size_op_arg()),
    Rcpp::Named("variables") = static_cast<double>(tape->fun.size_var()),
    Rcpp::Named("dynamic_independent") = static_cast<double>(tape->fun.size_dyn_ind()),
    Rcpp::Named("dynamic_parameters") = static_cast<double>(tape->fun.size_dyn_par()),
    Rcpp::Named("comparison_changes") = static_cast<double>(tape->fun.compare_change_number()),
    Rcpp::Named("comparison_change_operator") = static_cast<double>(tape->fun.compare_change_op_index()),
    Rcpp::Named("derivative_strategy") = tape->derivative_strategy,
    Rcpp::Named("jacobian_nonzeros") = static_cast<double>(tape->jacobian_nonzeros),
    Rcpp::Named("hessian_strategy") = tape->hessian_cache.strategy,
    Rcpp::Named("hessian_nonzeros") =
      static_cast<double>(tape->hessian_cache.nonzeros),
    Rcpp::Named("hessian_density") = tape->hessian_cache.density,
    Rcpp::Named("hessian_sweeps") =
      static_cast<double>(tape->hessian_cache.sweeps),
    Rcpp::Named("operation_sequence_bytes") =
      static_cast<double>(tape->fun.size_op_seq()),
    Rcpp::Named("random_access_bytes") =
      static_cast<double>(tape->fun.size_random()),
    Rcpp::Named("forward_sparsity_bytes") = static_cast<double>(
      tape->fun.size_forward_bool() + tape->fun.size_forward_set()),
    Rcpp::Named("taylor_bytes_proxy") = static_cast<double>(taylor_bytes),
    Rcpp::Named("resident_bytes_proxy") = static_cast<double>(
      tape->fun.size_op_seq() + tape->fun.size_random() +
      tape->fun.size_forward_bool() + tape->fun.size_forward_set() +
      taylor_bytes)
  );
}

// [[Rcpp::export(name = ".libertad_tape_graph_json")]]
std::string libertad_tape_graph_json(SEXP tape_pointer) {
  Rcpp::XPtr<TapeHandle> tape(tape_pointer);
  return tape->fun.to_json();
}

// [[Rcpp::export(name = ".libertad_tape_from_graph_json")]]
SEXP libertad_tape_from_graph_json(
    SEXP program_pointer, const std::string& graph_json,
    const Rcpp::CharacterVector& domain,
    const Rcpp::CharacterVector& dynamic,
    const Rcpp::NumericVector& dynamic_values,
    const Rcpp::CharacterVector& range) {
  Rcpp::XPtr<ProgramHandle> handle(program_pointer);
  std::vector<std::string> domain_names = character_vector(domain);
  std::vector<std::string> dynamic_names = character_vector(dynamic);
  std::vector<std::string> range_names = character_vector(range);
  std::vector<double> values = numeric_vector(dynamic_values);
  if (values.size() != dynamic_names.size()) {
    Rcpp::stop("Cached dynamic values do not match the dynamic input names.");
  }
  CppAD::ADFun<double> fun;
  fun.from_json(graph_json);
  if (fun.Domain() != domain_names.size() || fun.Range() != range_names.size() ||
      fun.size_dyn_ind() != dynamic_names.size()) {
    Rcpp::stop("Cached CppAD graph dimensions do not match its metadata.");
  }
  fun.new_dynamic(values);
  Rcpp::XPtr<TapeHandle> pointer(
    new TapeHandle(handle->program, std::move(fun), domain_names,
                   dynamic_names, values, range_names), true
  );
  pointer.attr("class") = Rcpp::CharacterVector::create(
    "libertad_tape_ptr", "externalptr");
  pointer.attr("domain") = Rcpp::wrap(domain_names);
  pointer.attr("dynamic") = Rcpp::wrap(dynamic_names);
  pointer.attr("range") = Rcpp::wrap(range_names);
  return pointer;
}

// [[Rcpp::export(name = ".libertad_tape_value")]]
Rcpp::NumericVector libertad_tape_value(SEXP tape_pointer,
                                         const Rcpp::NumericVector& x) {
  Rcpp::XPtr<TapeHandle> tape(tape_pointer);
  std::vector<double> value = tape_forward_zero(*tape, tape_point(*tape, x));
  return named_vector(value, tape->range);
}

// [[Rcpp::export(name = ".libertad_tape_jacobian")]]
Rcpp::NumericMatrix libertad_tape_jacobian(SEXP tape_pointer,
                                            const Rcpp::NumericVector& x) {
  Rcpp::XPtr<TapeHandle> tape(tape_pointer);
  const std::size_t nr = tape->range.size();
  const std::size_t nc = tape->domain.size();
  std::vector<double> jac = tape_jacobian(*tape, tape_point(*tape, x));
  Rcpp::NumericMatrix result(nr, nc);
  for (std::size_t i = 0; i < nr; ++i) {
    for (std::size_t j = 0; j < nc; ++j) result(i, j) = jac[i * nc + j];
  }
  result.attr("dimnames") = Rcpp::List::create(Rcpp::wrap(tape->range), Rcpp::wrap(tape->domain));
  return result;
}

// [[Rcpp::export(name = ".libertad_tape_hessian")]]
Rcpp::NumericMatrix libertad_tape_hessian(SEXP tape_pointer,
                                           const Rcpp::NumericVector& x) {
  Rcpp::XPtr<TapeHandle> tape(tape_pointer);
  if (tape->range.size() != 1U) Rcpp::stop("Hessian requires a scalar tape output.");
  const std::size_t n = tape->domain.size();
  std::vector<double> hessian = tape_hessian(*tape, tape_point(*tape, x));
  Rcpp::NumericMatrix result(n, n);
  for (std::size_t i = 0; i < n; ++i) {
    for (std::size_t j = 0; j < n; ++j) result(i, j) = hessian[i * n + j];
  }
  result.attr("dimnames") = Rcpp::List::create(Rcpp::wrap(tape->domain), Rcpp::wrap(tape->domain));
  return result;
}

// [[Rcpp::export(name = ".libertad_tape_value_gradient")]]
Rcpp::List libertad_tape_value_gradient(SEXP tape_pointer,
                                         const Rcpp::NumericVector& x) {
  Rcpp::XPtr<TapeHandle> tape(tape_pointer);
  if (tape->range.size() != 1U) Rcpp::stop("Gradient requires a scalar tape output.");
  std::vector<double> point = tape_point(*tape, x);
  std::vector<double> value = tape_forward_zero(*tape, point);
  std::vector<double> jac = tape_jacobian(*tape, point);
  return Rcpp::List::create(
    Rcpp::Named("value") = named_vector(value, tape->range),
    Rcpp::Named("gradient") = named_vector(jac, tape->domain)
  );
}

namespace {

using ADVector = CppAD::vector<CppAD::AD<double>>;

CppAD::ADFun<double> checkpoint_advan1_inner() {
  ADVector input(3), output(1);
  input[0] = 5.0;
  input[1] = 0.1;
  input[2] = 1.0;
  CppAD::Independent(input);
  output[0] = input[0] * CppAD::exp(-input[1] * input[2]);
  return CppAD::ADFun<double>(input, output);
}

CppAD::ADFun<double> checkpoint_matrix_inner() {
  ADVector input(6), output(2);
  for (std::size_t i = 0; i < input.size(); ++i) input[i] = 0.1 * (i + 1.0);
  CppAD::Independent(input);
  output[0] = input[0] * input[4] + input[1] * input[5];
  output[1] = input[2] * input[4] + input[3] * input[5];
  return CppAD::ADFun<double>(input, output);
}

CppAD::ADFun<double> repeated_advan1(
    CppAD::chkpoint_two<double>* checkpoint, int repetitions) {
  ADVector input(3), output(1);
  input[0] = 5.0;
  input[1] = 0.1;
  input[2] = 1.0;
  CppAD::Independent(input);
  CppAD::AD<double> state = input[0];
  for (int iteration = 0; iteration < repetitions; ++iteration) {
    if (checkpoint == nullptr) {
      state *= CppAD::exp(-input[1] * input[2]);
    } else {
      ADVector arguments(3), result(1);
      arguments[0] = state;
      arguments[1] = input[1];
      arguments[2] = input[2];
      (*checkpoint)(arguments, result);
      state = result[0];
    }
  }
  output[0] = state;
  CppAD::ADFun<double> fun(input, output);
  fun.optimize();
  return fun;
}

CppAD::ADFun<double> repeated_matrix(
    CppAD::chkpoint_two<double>* checkpoint, int repetitions) {
  ADVector input(6), output(2);
  for (std::size_t i = 0; i < input.size(); ++i) input[i] = 0.1 * (i + 1.0);
  CppAD::Independent(input);
  CppAD::AD<double> first = input[4];
  CppAD::AD<double> second = input[5];
  for (int iteration = 0; iteration < repetitions; ++iteration) {
    if (checkpoint == nullptr) {
      const CppAD::AD<double> next_first = input[0] * first + input[1] * second;
      const CppAD::AD<double> next_second = input[2] * first + input[3] * second;
      first = next_first;
      second = next_second;
    } else {
      ADVector arguments(6), result(2);
      arguments[0] = input[0]; arguments[1] = input[1];
      arguments[2] = input[2]; arguments[3] = input[3];
      arguments[4] = first; arguments[5] = second;
      (*checkpoint)(arguments, result);
      first = result[0]; second = result[1];
    }
  }
  output[0] = first; output[1] = second;
  CppAD::ADFun<double> fun(input, output);
  fun.optimize();
  return fun;
}

double forward_benchmark(CppAD::ADFun<double>& fun,
                         const std::vector<double>& point, int evaluations) {
  const auto started = std::chrono::steady_clock::now();
  for (int iteration = 0; iteration < evaluations; ++iteration) {
    fun.Forward(0, point);
  }
  const auto elapsed = std::chrono::steady_clock::now() - started;
  return std::chrono::duration<double, std::micro>(elapsed).count() /
    static_cast<double>(evaluations);
}

Rcpp::List checkpoint_case(const std::string& name,
                           CppAD::ADFun<double>& checkpoint_fun,
                           CppAD::ADFun<double>& direct_fun,
                           const std::vector<double>& point,
                           int evaluations) {
  const std::vector<double> checkpoint_value = checkpoint_fun.Forward(0, point);
  const std::vector<double> direct_value = direct_fun.Forward(0, point);
  const std::vector<double> checkpoint_jacobian = checkpoint_fun.Jacobian(point);
  const std::vector<double> direct_jacobian = direct_fun.Jacobian(point);
  auto maximum_difference = [](const std::vector<double>& left,
                               const std::vector<double>& right) {
    double result = 0.0;
    for (std::size_t i = 0; i < left.size(); ++i) {
      result = std::max(result, std::abs(left[i] - right[i]));
    }
    return result;
  };
  // This conversion exercises the exact nested-AD route used by LibeRation's
  // curvature tapes. It will fail immediately if a checkpoint is not
  // configured with use_base2ad=true.
  auto nested = checkpoint_fun.base2ad();
  ADVector nested_point(point.size());
  for (std::size_t i = 0; i < point.size(); ++i) nested_point[i] = point[i];
  nested.Forward(0, nested_point);
  return Rcpp::List::create(
    Rcpp::Named("name") = name,
    Rcpp::Named("checkpoint_operations") = static_cast<double>(checkpoint_fun.size_op()),
    Rcpp::Named("direct_operations") = static_cast<double>(direct_fun.size_op()),
    Rcpp::Named("operation_reduction") = static_cast<double>(direct_fun.size_op()) -
      static_cast<double>(checkpoint_fun.size_op()),
    Rcpp::Named("max_value_difference") = maximum_difference(checkpoint_value, direct_value),
    Rcpp::Named("max_jacobian_difference") =
      maximum_difference(checkpoint_jacobian, direct_jacobian),
    Rcpp::Named("checkpoint_microseconds") =
      forward_benchmark(checkpoint_fun, point, evaluations),
    Rcpp::Named("direct_microseconds") =
      forward_benchmark(direct_fun, point, evaluations),
    Rcpp::Named("nested_ad_safe") = true
  );
}

struct NormalQuadratureRule {
  Eigen::VectorXd nodes;
  Eigen::VectorXd weights;
};

NormalQuadratureRule standard_normal_gauss_hermite(int order) {
  Eigen::MatrixXd jacobi = Eigen::MatrixXd::Zero(order, order);
  for (int index = 1; index < order; ++index) {
    // Golub-Welsch recurrence for the standard-normal probability measure.
    const double off_diagonal = std::sqrt(static_cast<double>(index));
    jacobi(index - 1, index) = off_diagonal;
    jacobi(index, index - 1) = off_diagonal;
  }
  auto decomposition = libertad::detail::self_adjoint_eigen(jacobi);
  if (decomposition.info != Eigen::Success) {
    Rcpp::stop("Unable to construct the Gauss-Hermite rule.");
  }
  return NormalQuadratureRule{
    decomposition.values,
    decomposition.vectors.row(0).array().square().matrix()
  };
}

long double binomial_coefficient(int n, int k) {
  if (k < 0 || k > n) return 0.0L;
  k = std::min(k, n - k);
  long double result = 1.0L;
  for (int index = 1; index <= k; ++index) {
    result *= static_cast<long double>(n - k + index) /
      static_cast<long double>(index);
  }
  return result;
}

double canonical_sparse_node(double value) {
  return std::abs(value) <= 128.0 * std::numeric_limits<double>::epsilon() ?
    0.0 : value;
}

}  // namespace

// [[Rcpp::export(name = ".libertad_gauss_hermite_grid")]]
Rcpp::List libertad_gauss_hermite_grid(int order = 5,
                                       int dimension = 1,
                                       double max_points = 100000.0) {
  if (order < 1 || order > 50) {
    Rcpp::stop("`order` must be between 1 and 50.");
  }
  if (dimension < 0 || dimension > 20) {
    Rcpp::stop("`dimension` must be between 0 and 20.");
  }
  if (!std::isfinite(max_points) || max_points < 1.0) {
    Rcpp::stop("`max_points` must be one positive finite number.");
  }
  if (max_points > static_cast<double>(
        std::numeric_limits<std::size_t>::max())) {
    Rcpp::stop("`max_points` exceeds the platform allocation limit.");
  }

  std::size_t points = 1U;
  const std::size_t limit = static_cast<std::size_t>(std::floor(max_points));
  for (int axis = 0; axis < dimension; ++axis) {
    if (points > limit / static_cast<std::size_t>(order)) {
      Rcpp::stop(
        "The requested tensor Gauss-Hermite grid exceeds `max_points` "
        "(%d^%d > %.0f). Reduce `order` or ETA dimension, or use IMP/SAEM.",
        order, dimension, max_points
      );
    }
    points *= static_cast<std::size_t>(order);
  }

  const NormalQuadratureRule rule = standard_normal_gauss_hermite(order);

  Rcpp::NumericMatrix nodes(static_cast<R_xlen_t>(points), dimension);
  Rcpp::NumericVector log_weights(static_cast<R_xlen_t>(points));
  for (std::size_t point = 0U; point < points; ++point) {
    std::size_t code = point;
    double log_weight = 0.0;
    for (int axis = 0; axis < dimension; ++axis) {
      const int index = static_cast<int>(code % static_cast<std::size_t>(order));
      code /= static_cast<std::size_t>(order);
      nodes(static_cast<R_xlen_t>(point), axis) = rule.nodes[index];
      log_weight += std::log(rule.weights[index]);
    }
    log_weights[static_cast<R_xlen_t>(point)] = log_weight;
  }

  return Rcpp::List::create(
    Rcpp::Named("nodes") = nodes,
    Rcpp::Named("log_weights") = log_weights,
    Rcpp::Named("log_abs_weights") = log_weights,
    Rcpp::Named("weights") = Rcpp::exp(log_weights),
    Rcpp::Named("signs") = Rcpp::rep(1.0, static_cast<R_xlen_t>(points)),
    Rcpp::Named("order") = order,
    Rcpp::Named("dimension") = dimension,
    Rcpp::Named("points") = static_cast<double>(points),
    Rcpp::Named("grid") = "tensor",
    Rcpp::Named("measure") = "standard-normal"
  );
}

// [[Rcpp::export(name = ".libertad_smolyak_gauss_hermite_grid")]]
Rcpp::List libertad_smolyak_gauss_hermite_grid(int level = 3,
                                               int dimension = 4,
                                               double max_points = 100000.0) {
  if (level < 1 || level > 25) {
    Rcpp::stop("`level` must be between 1 and 25.");
  }
  if (dimension < 0 || dimension > 20) {
    Rcpp::stop("`dimension` must be between 0 and 20.");
  }
  if (!std::isfinite(max_points) || max_points < 1.0) {
    Rcpp::stop("`max_points` must be one positive finite number.");
  }
  if (max_points > static_cast<double>(
        std::numeric_limits<std::size_t>::max())) {
    Rcpp::stop("`max_points` exceeds the platform allocation limit.");
  }

  const std::size_t limit = static_cast<std::size_t>(std::floor(max_points));
  if (dimension == 0) {
    return Rcpp::List::create(
      Rcpp::Named("nodes") = Rcpp::NumericMatrix(1, 0),
      Rcpp::Named("log_weights") = Rcpp::NumericVector::create(0.0),
      Rcpp::Named("log_abs_weights") = Rcpp::NumericVector::create(0.0),
      Rcpp::Named("weights") = Rcpp::NumericVector::create(1.0),
      Rcpp::Named("signs") = Rcpp::NumericVector::create(1.0),
      Rcpp::Named("level") = level,
      Rcpp::Named("dimension") = dimension,
      Rcpp::Named("points") = 1.0,
      Rcpp::Named("candidate_points") = 1.0,
      Rcpp::Named("negative_weights") = 0,
      Rcpp::Named("grid") = "smolyak",
      Rcpp::Named("growth") = "odd-linear",
      Rcpp::Named("measure") = "standard-normal"
    );
  }

  std::vector<NormalQuadratureRule> one_dimensional;
  one_dimensional.reserve(static_cast<std::size_t>(level));
  for (int index = 1; index <= level; ++index) {
    one_dimensional.push_back(standard_normal_gauss_hermite(2 * index - 1));
  }

  std::map<std::vector<double>, long double> accumulated;
  std::vector<int> indices(static_cast<std::size_t>(dimension), 1);
  std::vector<double> point(static_cast<std::size_t>(dimension), 0.0);
  std::size_t candidate_points = 0U;
  const std::size_t candidate_limit = limit >
      std::numeric_limits<std::size_t>::max() / 64U ?
    std::numeric_limits<std::size_t>::max() :
      std::max(limit * static_cast<std::size_t>(64U),
               static_cast<std::size_t>(4096U));

  auto add_tensor = [&](const std::vector<int>& tensor_levels,
                        long double coefficient) {
    std::function<void(int, long double)> expand;
    expand = [&](int axis, long double weight) {
      if (axis == dimension) {
        ++candidate_points;
        if (candidate_points > candidate_limit) {
          Rcpp::stop(
            "The requested Smolyak construction exceeds its safe intermediate "
            "work limit. Reduce `level` or ETA dimension, increase "
            "`max_points`, or use IMP/SAEM."
          );
        }
        accumulated[point] += coefficient * weight;
        return;
      }
      const NormalQuadratureRule& rule = one_dimensional[
        static_cast<std::size_t>(tensor_levels[static_cast<std::size_t>(axis)] - 1)
      ];
      for (Eigen::Index node = 0; node < rule.nodes.size(); ++node) {
        point[static_cast<std::size_t>(axis)] =
          canonical_sparse_node(rule.nodes[node]);
        expand(axis + 1, weight * static_cast<long double>(rule.weights[node]));
      }
    };
    expand(0, 1.0L);
  };

  const int upper_sum = level + dimension - 1;
  for (int target_sum = level; target_sum <= upper_sum; ++target_sum) {
    const int difference = upper_sum - target_sum;
    long double coefficient = binomial_coefficient(dimension - 1, difference);
    if (difference % 2 != 0) coefficient = -coefficient;
    std::function<void(int, int)> compositions;
    compositions = [&](int axis, int remaining) {
      if (axis == dimension - 1) {
        if (remaining >= 1 && remaining <= level) {
          indices[static_cast<std::size_t>(axis)] = remaining;
          add_tensor(indices, coefficient);
        }
        return;
      }
      const int axes_left = dimension - axis - 1;
      const int maximum = std::min(level, remaining - axes_left);
      for (int value = 1; value <= maximum; ++value) {
        indices[static_cast<std::size_t>(axis)] = value;
        compositions(axis + 1, remaining - value);
      }
    };
    compositions(0, target_sum);
  }

  long double accumulated_absolute = 0.0L;
  for (const auto& entry : accumulated) {
    accumulated_absolute += std::abs(entry.second);
  }
  const long double drop_tolerance = 128.0L *
    std::numeric_limits<long double>::epsilon() *
    std::max(1.0L, accumulated_absolute);
  std::vector<std::pair<std::vector<double>, long double>> retained;
  retained.reserve(accumulated.size());
  long double total_weight = 0.0L;
  for (const auto& entry : accumulated) {
    if (std::abs(entry.second) > drop_tolerance) {
      retained.push_back(entry);
      total_weight += entry.second;
    }
  }
  if (retained.size() > limit) {
    Rcpp::stop(
      "The requested Smolyak Gauss-Hermite grid exceeds `max_points` "
      "(%lld > %.0f). Reduce `level` or ETA dimension, or use IMP/SAEM.",
      static_cast<long long>(retained.size()), max_points
    );
  }
  if (!std::isfinite(static_cast<double>(total_weight)) ||
      std::abs(total_weight) <= drop_tolerance) {
    Rcpp::stop("The Smolyak combination produced an invalid total weight.");
  }

  const R_xlen_t points = static_cast<R_xlen_t>(retained.size());
  Rcpp::NumericMatrix nodes(points, dimension);
  Rcpp::NumericVector weights(points), signs(points), log_abs_weights(points);
  int negative_weights = 0;
  for (R_xlen_t row = 0; row < points; ++row) {
    const auto& entry = retained[static_cast<std::size_t>(row)];
    const double weight = static_cast<double>(entry.second / total_weight);
    weights[row] = weight;
    signs[row] = weight < 0.0 ? -1.0 : 1.0;
    log_abs_weights[row] = std::log(std::abs(weight));
    if (weight < 0.0) ++negative_weights;
    for (int axis = 0; axis < dimension; ++axis) {
      nodes(row, axis) = entry.first[static_cast<std::size_t>(axis)];
    }
  }

  return Rcpp::List::create(
    Rcpp::Named("nodes") = nodes,
    // Kept as an alias for code that consumes log masses; sparse-grid users
    // must combine it with `signs`.
    Rcpp::Named("log_weights") = log_abs_weights,
    Rcpp::Named("log_abs_weights") = log_abs_weights,
    Rcpp::Named("weights") = weights,
    Rcpp::Named("signs") = signs,
    Rcpp::Named("level") = level,
    Rcpp::Named("dimension") = dimension,
    Rcpp::Named("points") = static_cast<double>(points),
    Rcpp::Named("candidate_points") = static_cast<double>(candidate_points),
    Rcpp::Named("negative_weights") = negative_weights,
    Rcpp::Named("grid") = "smolyak",
    Rcpp::Named("growth") = "odd-linear",
    Rcpp::Named("measure") = "standard-normal"
  );
}

// [[Rcpp::export(name = ".libertad_checkpoint_probe")]]
Rcpp::List libertad_checkpoint_probe(int repetitions = 64,
                                     int evaluations = 1000) {
  if (repetitions < 2 || repetitions > 10000) {
    Rcpp::stop("`repetitions` must be between 2 and 10000.");
  }
  if (evaluations < 1 || evaluations > 1000000) {
    Rcpp::stop("`evaluations` must be between 1 and 1000000.");
  }
  CppAD::ADFun<double> advan_inner = checkpoint_advan1_inner();
  CppAD::chkpoint_two<double> advan_checkpoint(
    advan_inner, "libertad_advan1_interval", true, true, true, false);
  CppAD::ADFun<double> advan_atomic = repeated_advan1(&advan_checkpoint, repetitions);
  CppAD::ADFun<double> advan_direct = repeated_advan1(nullptr, repetitions);

  CppAD::ADFun<double> matrix_inner = checkpoint_matrix_inner();
  CppAD::chkpoint_two<double> matrix_checkpoint(
    matrix_inner, "libertad_matrix2_multiply", true, true, true, false);
  CppAD::ADFun<double> matrix_atomic = repeated_matrix(&matrix_checkpoint, repetitions);
  CppAD::ADFun<double> matrix_direct = repeated_matrix(nullptr, repetitions);
  return Rcpp::List::create(
    Rcpp::Named("repetitions") = repetitions,
    Rcpp::Named("evaluations") = evaluations,
    Rcpp::Named("advan1") = checkpoint_case(
      "ADVAN1 interval", advan_atomic, advan_direct,
      std::vector<double>{5.0, 0.1, 1.0}, evaluations),
    Rcpp::Named("matrix2") = checkpoint_case(
      "2x2 matrix state update", matrix_atomic, matrix_direct,
      std::vector<double>{0.8, 0.1, 0.05, 0.9, 1.0, 0.5}, evaluations)
  );
}

// [[Rcpp::export(name = ".libertad_engine_info")]]
Rcpp::List libertad_engine_info() {
  return Rcpp::List::create(
    Rcpp::Named("backend") = "CppAD (bundled by LibeRtAD)",
    Rcpp::Named("cppad_version") = CPPAD_PACKAGE_STRING,
    Rcpp::Named("cppad_source_commit") = libertad::cppad_source_commit,
    Rcpp::Named("eigen_version") = libertad::eigen_version,
    Rcpp::Named("eigen_source_commit") = libertad::eigen_source_commit,
    Rcpp::Named("scalar") = "double",
    Rcpp::Named("persistent_tape") = true,
    Rcpp::Named("cpp_standard") = 17,
    Rcpp::Named("thread_state") = "one independent tape per ADModel"
  );
}

// [[Rcpp::export(name = ".libertad_allocator_info")]]
Rcpp::List libertad_allocator_info(bool release_available = false) {
  const std::size_t thread = CppAD::thread_alloc::thread_num();
  const std::size_t before = CppAD::thread_alloc::available(thread);
  if (release_available) {
    CppAD::thread_alloc::free_available(thread);
  }
  return Rcpp::List::create(
    Rcpp::Named("thread") = static_cast<double>(thread),
    Rcpp::Named("threads_configured") =
      static_cast<double>(CppAD::thread_alloc::num_threads()),
    Rcpp::Named("in_parallel") = CppAD::thread_alloc::in_parallel(),
    Rcpp::Named("inuse_bytes") =
      static_cast<double>(CppAD::thread_alloc::inuse(thread)),
    Rcpp::Named("available_bytes") =
      static_cast<double>(CppAD::thread_alloc::available(thread)),
    Rcpp::Named("released_bytes") =
      static_cast<double>(before -
        CppAD::thread_alloc::available(thread))
  );
}
