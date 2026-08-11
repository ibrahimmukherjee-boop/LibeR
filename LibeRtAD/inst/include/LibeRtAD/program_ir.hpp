#ifndef LIBERTAD_PROGRAM_IR_HPP
#define LIBERTAD_PROGRAM_IR_HPP

#include <string>
#include <vector>

namespace libertad {

enum class Op : int {
  input = 0,
  constant = 1,
  add = 2,
  sub = 3,
  mul = 4,
  div = 5,
  pow = 6,
  neg = 7,
  exp = 8,
  log = 9,
  sqrt = 10,
  sin = 11,
  cos = 12,
  tan = 13,
  tanh = 14,
  abs = 15,
  expm1 = 16,
  log1p = 17,
  min = 18,
  max = 19,
  cond_lt = 20,
  cond_le = 21,
  cond_gt = 22,
  cond_ge = 23,
  cond_eq = 24,
  cond_ne = 25
};

struct Node {
  Op op = Op::constant;
  int a = -1;
  int b = -1;
  int c = -1;
  int d = -1;
  double value = 0.0;
  std::string label;
};

// Standard-C++ value representation of a parsed LibeRtAD program. It can be
// constructed, serialized, and retained without R or Rcpp; program.hpp owns
// the explicit adapter from the R parser's list representation.
struct ProgramIR {
  int version = 1;
  std::vector<std::string> input_names;
  std::vector<Node> nodes;
  std::vector<std::string> output_names;
  std::vector<int> output_nodes;
};

}  // namespace libertad

#endif
