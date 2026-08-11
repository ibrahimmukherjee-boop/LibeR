#ifndef LIBERTAD_PROGRAM_HPP
#define LIBERTAD_PROGRAM_HPP

#include <LibeRtAD/cppad_r_output.hpp>
#include <LibeRtAD/program_ir.hpp>
#include <LibeRtAD/sparse_hessian.hpp>

#include <algorithm>
#include <cmath>
#include <memory>
#include <stdexcept>
#include <type_traits>
#include <unordered_map>
#include <utility>
#include <vector>

namespace libertad {

inline int normalize_ir_reference(Op op, int value, bool first) {
  if (op == Op::input && first) return value - 1;
  if (value <= 0) return -1;
  return value - 1;
}

inline ProgramIR program_ir_from_r(const Rcpp::List& ir) {
  ProgramIR result;
  result.version = Rcpp::as<int>(ir["version"]);
  result.input_names = Rcpp::as<std::vector<std::string>>(ir["input_names"]);
  result.output_names = Rcpp::as<std::vector<std::string>>(ir["output_names"]);
  Rcpp::IntegerVector output = ir["output_nodes"];
  result.output_nodes.reserve(static_cast<std::size_t>(output.size()));
  for (int value : output) result.output_nodes.push_back(value - 1);
  Rcpp::List source = ir["nodes"];
  result.nodes.reserve(static_cast<std::size_t>(source.size()));
  for (R_xlen_t index = 0; index < source.size(); ++index) {
    Rcpp::List item = source[index];
    Node node;
    node.op = static_cast<Op>(Rcpp::as<int>(item["op"]));
    node.a = normalize_ir_reference(node.op, Rcpp::as<int>(item["a"]), true);
    node.b = normalize_ir_reference(node.op, Rcpp::as<int>(item["b"]), false);
    node.c = normalize_ir_reference(node.op, Rcpp::as<int>(item["c"]), false);
    node.d = normalize_ir_reference(node.op, Rcpp::as<int>(item["d"]), false);
    node.value = Rcpp::as<double>(item["value"]);
    node.label = Rcpp::as<std::string>(item["label"]);
    result.nodes.push_back(std::move(node));
  }
  return result;
}

template <class Scalar>
inline Scalar scalar_exp(const Scalar& x) {
  using std::exp;
  return exp(x);
}

template <class Scalar>
inline Scalar scalar_log(const Scalar& x) {
  using std::log;
  return log(x);
}

template <class Scalar>
inline Scalar scalar_sqrt(const Scalar& x) {
  using std::sqrt;
  return sqrt(x);
}

template <class Scalar>
inline Scalar scalar_sin(const Scalar& x) {
  using std::sin;
  return sin(x);
}

template <class Scalar>
inline Scalar scalar_cos(const Scalar& x) {
  using std::cos;
  return cos(x);
}

template <class Scalar>
inline Scalar scalar_tan(const Scalar& x) {
  using std::tan;
  return tan(x);
}

template <class Scalar>
inline Scalar scalar_tanh(const Scalar& x) {
  using std::tanh;
  return tanh(x);
}

template <class Scalar>
inline Scalar scalar_abs(const Scalar& x) {
  using std::abs;
  return abs(x);
}

template <class Scalar>
inline Scalar scalar_pow(const Scalar& x, const Scalar& y) {
  using std::pow;
  return pow(x, y);
}

template <class Scalar>
inline Scalar choose_lt(const Scalar& left, const Scalar& right,
                        const Scalar& yes, const Scalar& no) {
  return CppAD::CondExpLt(left, right, yes, no);
}
inline CppAD::AD<double> choose_lt(
    const CppAD::AD<double>& left, const CppAD::AD<double>& right,
    const CppAD::AD<double>& yes, const CppAD::AD<double>& no) {
  if (CppAD::Parameter(left) && !CppAD::Dynamic(left) &&
      CppAD::Parameter(right) && !CppAD::Dynamic(right)) {
    return CppAD::Value(left) < CppAD::Value(right) ? yes : no;
  }
  return CppAD::CondExpLt(left, right, yes, no);
}
inline double choose_lt(double left, double right, double yes, double no) {
  return left < right ? yes : no;
}

template <class Scalar>
inline Scalar choose_le(const Scalar& left, const Scalar& right,
                        const Scalar& yes, const Scalar& no) {
  return CppAD::CondExpLe(left, right, yes, no);
}
inline CppAD::AD<double> choose_le(
    const CppAD::AD<double>& left, const CppAD::AD<double>& right,
    const CppAD::AD<double>& yes, const CppAD::AD<double>& no) {
  if (CppAD::Parameter(left) && !CppAD::Dynamic(left) &&
      CppAD::Parameter(right) && !CppAD::Dynamic(right)) {
    return CppAD::Value(left) <= CppAD::Value(right) ? yes : no;
  }
  return CppAD::CondExpLe(left, right, yes, no);
}
inline double choose_le(double left, double right, double yes, double no) {
  return left <= right ? yes : no;
}

template <class Scalar>
inline Scalar choose_gt(const Scalar& left, const Scalar& right,
                        const Scalar& yes, const Scalar& no) {
  return CppAD::CondExpGt(left, right, yes, no);
}
inline CppAD::AD<double> choose_gt(
    const CppAD::AD<double>& left, const CppAD::AD<double>& right,
    const CppAD::AD<double>& yes, const CppAD::AD<double>& no) {
  if (CppAD::Parameter(left) && !CppAD::Dynamic(left) &&
      CppAD::Parameter(right) && !CppAD::Dynamic(right)) {
    return CppAD::Value(left) > CppAD::Value(right) ? yes : no;
  }
  return CppAD::CondExpGt(left, right, yes, no);
}
inline double choose_gt(double left, double right, double yes, double no) {
  return left > right ? yes : no;
}

template <class Scalar>
inline Scalar choose_ge(const Scalar& left, const Scalar& right,
                        const Scalar& yes, const Scalar& no) {
  return CppAD::CondExpGe(left, right, yes, no);
}
inline CppAD::AD<double> choose_ge(
    const CppAD::AD<double>& left, const CppAD::AD<double>& right,
    const CppAD::AD<double>& yes, const CppAD::AD<double>& no) {
  if (CppAD::Parameter(left) && !CppAD::Dynamic(left) &&
      CppAD::Parameter(right) && !CppAD::Dynamic(right)) {
    return CppAD::Value(left) >= CppAD::Value(right) ? yes : no;
  }
  return CppAD::CondExpGe(left, right, yes, no);
}
inline double choose_ge(double left, double right, double yes, double no) {
  return left >= right ? yes : no;
}

template <class Scalar>
inline Scalar choose_eq(const Scalar& left, const Scalar& right,
                        const Scalar& yes, const Scalar& no) {
  return CppAD::CondExpEq(left, right, yes, no);
}
inline CppAD::AD<double> choose_eq(
    const CppAD::AD<double>& left, const CppAD::AD<double>& right,
    const CppAD::AD<double>& yes, const CppAD::AD<double>& no) {
  if (CppAD::Parameter(left) && !CppAD::Dynamic(left) &&
      CppAD::Parameter(right) && !CppAD::Dynamic(right)) {
    return CppAD::Value(left) == CppAD::Value(right) ? yes : no;
  }
  return CppAD::CondExpEq(left, right, yes, no);
}
inline double choose_eq(double left, double right, double yes, double no) {
  return left == right ? yes : no;
}

template <class Scalar>
inline Scalar choose_ne(const Scalar& left, const Scalar& right,
                        const Scalar& yes, const Scalar& no) {
  return CppAD::CondExpEq(left, right, no, yes);
}
inline CppAD::AD<double> choose_ne(
    const CppAD::AD<double>& left, const CppAD::AD<double>& right,
    const CppAD::AD<double>& yes, const CppAD::AD<double>& no) {
  if (CppAD::Parameter(left) && !CppAD::Dynamic(left) &&
      CppAD::Parameter(right) && !CppAD::Dynamic(right)) {
    return CppAD::Value(left) != CppAD::Value(right) ? yes : no;
  }
  return CppAD::CondExpEq(left, right, no, yes);
}
inline double choose_ne(double left, double right, double yes, double no) {
  return left != right ? yes : no;
}

class Program {
 public:
  int version = 1;
  std::vector<std::string> input_names;
  std::vector<Node> nodes;
  std::vector<std::string> output_names;
  std::vector<int> output_nodes;
  std::unordered_map<std::string, std::size_t> input_positions;
  std::unordered_map<std::string, std::size_t> output_positions;

  explicit Program(ProgramIR ir)
      : version(ir.version), input_names(std::move(ir.input_names)),
        nodes(std::move(ir.nodes)), output_names(std::move(ir.output_names)),
        output_nodes(std::move(ir.output_nodes)) {
    for (std::size_t index = 0; index < nodes.size(); ++index) {
      validate_node(nodes[index], static_cast<int>(index));
    }
    if (output_names.size() != output_nodes.size()) {
      throw std::invalid_argument("IR output names/nodes have different lengths.");
    }
    for (std::size_t i = 0; i < input_names.size(); ++i) {
      if (!input_positions.emplace(input_names[i], i).second) {
        throw std::invalid_argument("Duplicate IR input name: " + input_names[i]);
      }
    }
    for (std::size_t i = 0; i < output_names.size(); ++i) {
      if (output_nodes[i] < 0 || output_nodes[i] >= static_cast<int>(nodes.size())) {
        throw std::invalid_argument("IR output node is out of range.");
      }
      if (!output_positions.emplace(output_names[i], i).second) {
        throw std::invalid_argument("Duplicate IR output name: " + output_names[i]);
      }
    }
  }

  explicit Program(const Rcpp::List& ir) : Program(program_ir_from_r(ir)) {}

  template <class Scalar>
  std::vector<Scalar> eval_all(const std::vector<Scalar>& inputs) const {
    if (inputs.size() != input_names.size()) {
      throw std::invalid_argument("Program input vector has the wrong length.");
    }
    std::vector<Scalar> values(nodes.size(), Scalar(0.0));
    for (std::size_t i = 0; i < nodes.size(); ++i) {
      const Node& n = nodes[i];
      switch (n.op) {
        case Op::input: values[i] = inputs.at(static_cast<std::size_t>(n.a)); break;
        case Op::constant: values[i] = Scalar(n.value); break;
        case Op::add: values[i] = values[n.a] + values[n.b]; break;
        case Op::sub: values[i] = values[n.a] - values[n.b]; break;
        case Op::mul: values[i] = values[n.a] * values[n.b]; break;
        case Op::div: values[i] = values[n.a] / values[n.b]; break;
        case Op::pow: values[i] = scalar_pow(values[n.a], values[n.b]); break;
        case Op::neg: values[i] = -values[n.a]; break;
        case Op::exp: values[i] = scalar_exp(values[n.a]); break;
        case Op::log: values[i] = scalar_log(values[n.a]); break;
        case Op::sqrt: values[i] = scalar_sqrt(values[n.a]); break;
        case Op::sin: values[i] = scalar_sin(values[n.a]); break;
        case Op::cos: values[i] = scalar_cos(values[n.a]); break;
        case Op::tan: values[i] = scalar_tan(values[n.a]); break;
        case Op::tanh: values[i] = scalar_tanh(values[n.a]); break;
        case Op::abs: values[i] = scalar_abs(values[n.a]); break;
        case Op::expm1: values[i] = scalar_exp(values[n.a]) - Scalar(1.0); break;
        case Op::log1p: values[i] = scalar_log(Scalar(1.0) + values[n.a]); break;
        case Op::min: values[i] = choose_lt(values[n.a], values[n.b], values[n.a], values[n.b]); break;
        case Op::max: values[i] = choose_gt(values[n.a], values[n.b], values[n.a], values[n.b]); break;
        case Op::cond_lt: values[i] = choose_lt(values[n.a], values[n.b], values[n.c], values[n.d]); break;
        case Op::cond_le: values[i] = choose_le(values[n.a], values[n.b], values[n.c], values[n.d]); break;
        case Op::cond_gt: values[i] = choose_gt(values[n.a], values[n.b], values[n.c], values[n.d]); break;
        case Op::cond_ge: values[i] = choose_ge(values[n.a], values[n.b], values[n.c], values[n.d]); break;
        case Op::cond_eq: values[i] = choose_eq(values[n.a], values[n.b], values[n.c], values[n.d]); break;
        case Op::cond_ne: values[i] = choose_ne(values[n.a], values[n.b], values[n.c], values[n.d]); break;
        default: throw std::runtime_error("Unknown expression IR opcode.");
      }
    }
    return values;
  }

  template <class Scalar>
  std::vector<Scalar> eval_outputs(const std::vector<Scalar>& inputs,
                                   const std::vector<std::size_t>& selected) const {
    std::vector<Scalar> values = eval_all(inputs);
    std::vector<Scalar> result;
    result.reserve(selected.size());
    for (std::size_t output : selected) {
      result.push_back(values.at(static_cast<std::size_t>(output_nodes.at(output))));
    }
    return result;
  }

  std::vector<std::size_t> select_outputs(const std::vector<std::string>& names) const {
    std::vector<std::size_t> selected;
    selected.reserve(names.size());
    for (const std::string& name : names) {
      auto it = output_positions.find(name);
      if (it == output_positions.end()) {
        throw std::invalid_argument("Unknown program output: " + name);
      }
      selected.push_back(it->second);
    }
    return selected;
  }

 private:
  static int arity(Op op) {
    if (op == Op::input || op == Op::constant) return 0;
    if (op == Op::neg || (op >= Op::exp && op <= Op::log1p)) return 1;
    if (op >= Op::cond_lt) return 4;
    return 2;
  }

  void validate_node(const Node& node, int position) const {
    const int op_value = static_cast<int>(node.op);
    if (op_value < static_cast<int>(Op::input) || op_value > static_cast<int>(Op::cond_ne)) {
      throw std::invalid_argument("IR contains an invalid opcode.");
    }
    if (node.op == Op::input) {
      if (node.a < 0 || node.a >= static_cast<int>(input_names.size())) {
        throw std::invalid_argument("IR input index is out of range.");
      }
      return;
    }
    const int n_args = arity(node.op);
    const int refs[4] = {node.a, node.b, node.c, node.d};
    for (int i = 0; i < n_args; ++i) {
      if (refs[i] < 0 || refs[i] >= position) {
        throw std::invalid_argument("IR node refers to a missing or future node.");
      }
    }
  }
};

struct ProgramHandle {
  explicit ProgramHandle(const Rcpp::List& ir)
      : program(std::make_shared<const Program>(ir)) {}
  std::shared_ptr<const Program> program;
};

struct TapeHandle {
  TapeHandle(std::shared_ptr<const Program> program_in,
             CppAD::ADFun<double>&& fun_in,
             std::vector<std::string> domain_in,
             std::vector<std::string> dynamic_in,
             std::vector<double> dynamic_values_in,
             std::vector<std::string> range_in)
      : program(std::move(program_in)), fun(std::move(fun_in)),
        domain(std::move(domain_in)), dynamic(std::move(dynamic_in)),
        dynamic_values(std::move(dynamic_values_in)), range(std::move(range_in)) {}

  std::shared_ptr<const Program> program;
  CppAD::ADFun<double> fun;
  std::vector<std::string> domain;
  std::vector<std::string> dynamic;
  std::vector<double> dynamic_values;
  std::vector<std::string> range;
  std::string derivative_strategy = "not-evaluated";
  std::size_t jacobian_nonzeros = 0;
  SparseHessianCache hessian_cache;
};

}  // namespace libertad

#endif
