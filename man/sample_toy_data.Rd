% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/toy_data.R
\name{sample_toy_data}
\alias{sample_toy_data}
\title{Samples toy two block JIVE data.}
\usage{
sample_toy_data(
  n = 200,
  dx = 100,
  dy = 500,
  sigma = 0.5,
  only_observations = TRUE
)
}
\arguments{
\item{n}{Integer. Number of observations. Must be divisible by 20.}

\item{dx}{Integer. Dimension of X block. Must be divisible by 2.}

\item{dy}{Integer. Dimension of Y block. Must be divisible by 10.}

\item{sigma}{Float. Noise strength.}

\item{only_observations}{Boolean. Whether or not to include the true decomposition.}
}
\value{
A list of length 2 with the sampled data.
    Each list contains: obs, joint, individual, and noise.
}
\description{
\code{sample_toy_data} samples the two block distribution from AJIVE figure 2.
}
\details{
Note AJIVE figure 2 uses n=100, dx=100 and dy=10000 and sigma=1.
}
\examples{
blocks <- sample_toy_data()
X1 = blocks[[1]]
}
