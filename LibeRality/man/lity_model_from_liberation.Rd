\name{lity_model_from_liberation}
\alias{lity_model_from_liberation}
\title{Import a LibeRation model version or completed estimation}
\usage{
lity_model_from_liberation(
  workspace,
  project,
  snapshot = "latest",
  use_estimates = TRUE
)
}
\arguments{
\item{workspace}{LibeRation workspace object or path.}
\item{project}{Project identifier.}
\item{snapshot}{Model-version or run identifier.}
\item{use_estimates}{Use final estimates from a completed estimation run.}
}
\value{
A LibeRation \code{nm_model} with import provenance.
}
\description{
A model-version selection uses its stored initial parameter values. A
completed estimation run uses its final THETA, OMEGA, and SIGMA estimates
when requested. The imported object is copied so later workspace changes
cannot silently alter an existing design.
}
