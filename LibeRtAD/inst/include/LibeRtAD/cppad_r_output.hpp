#ifndef LIBERTAD_CPPAD_R_OUTPUT_HPP
#define LIBERTAD_CPPAD_R_OUTPUT_HPP

#include <Rcpp.h>
#include <R_ext/Utils.h>
#include <Rembedded.h>

#include <cstdarg>

// LibeRtAD bundles the official CppAD release 20260000.0 at commit
// 5d51b2aa6d6874c8d561da298a90b3721550d45d. CppAD contains
// diagnostic and error branches that write directly to std::cout/std::cerr or
// std::printf, and its last-resort default error handler calls std::exit. R
// extensions must use R's console and exception machinery instead. Keep the
// redirection local to the CppAD include so it cannot alter client code or the
// official headers.
//
// CppAD spells the streams both as qualified names and as unqualified names
// after `using`. Replacing each identifier while parsing the headers therefore
// requires the replacement to be a member of `std`.
namespace std {
inline Rcpp::Rostream<true> cppad_r_output;
inline Rcpp::Rostream<false> cppad_r_error;
[[noreturn]] inline void cppad_r_exit(int) {
  throw Rcpp::exception(
    "CppAD requested process termination; execution was returned safely to R.",
    false
  );
}
inline int cppad_r_printf(const char* format, ...) {
  std::va_list arguments;
  va_start(arguments, format);
  Rvprintf(format, arguments);
  va_end(arguments);
  return 0;
}
}

#define cout cppad_r_output
#define cerr cppad_r_error
#define printf cppad_r_printf
#define exit cppad_r_exit
#pragma push_macro("NDEBUG")
#ifndef NDEBUG
#define NDEBUG
#endif
#include <cppad/cppad.hpp>
#pragma pop_macro("NDEBUG")
#undef exit
#undef printf
#undef cerr
#undef cout

// The header-only LibeRtAD interface is consumed by downstream R packages,
// which do not link against CppAD's optional cppad_lib target. Current CppAD
// uses this one library helper only when it needs to persist a NaN diagnostic.
// Supply the R-session equivalent inline so every consumer remains
// self-contained and uses R's private temporary directory instead of an
// unsafe process-global temporary filename.
namespace CppAD { namespace local {
inline std::string temp_file(void) {
  char* path = R_tmpnam2("cppad-", R_TempDir, ".bin");
  if (path == nullptr) {
    throw Rcpp::exception("Unable to allocate a temporary CppAD diagnostic file.", false);
  }
  std::string result(path);
  R_free_tmpnam(path);
  return result;
}
} }

namespace libertad {
inline constexpr const char* cppad_source_commit =
  "5d51b2aa6d6874c8d561da298a90b3721550d45d";
}

#endif
