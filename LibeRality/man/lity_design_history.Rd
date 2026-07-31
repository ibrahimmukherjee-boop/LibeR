\name{lity_design_history}
\alias{lity_design_history}
\alias{lity_design_version_save}
\alias{lity_design_version_load}
\title{Persist and restore LibeRality design versions}
\usage{
lity_design_history(workspace = NULL)

lity_design_version_save(
  design,
  workspace = NULL,
  series_id = NULL,
  series_name = NULL,
  label = NULL
)

lity_design_version_load(
  workspace = NULL,
  series_id,
  version_id = "latest"
)
}
\arguments{
\item{workspace}{A LibeR workspace path or an \code{nm_workspace}.}

\item{design}{A validated \code{lity_design}.}

\item{series_id}{An existing design-series identifier. Omit it when saving to
start a new design history.}

\item{series_name}{A human-readable name for the design series.}

\item{label}{An optional version label. A blank label is replaced by a
sequential label such as \code{Version 001}.}

\item{version_id}{A version identifier, version label, version number, or
\code{"latest"}.}
}
\value{
\code{lity_design_history()} returns one data-frame row per immutable version.
\code{lity_design_version_save()} invisibly returns the saved version record.
\code{lity_design_version_load()} returns the validated \code{lity_design}.
}
\description{
Save complete immutable design objects under the shared LibeR workspace, list
the available current and previous designs, and restore a selected version.
Portable RDS import and export are independent of this workspace history.
}
