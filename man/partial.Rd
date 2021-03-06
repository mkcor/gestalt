% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/partial.R
\name{partial}
\alias{partial}
\alias{departial}
\title{Fix a Number of Arguments to a Function}
\usage{
partial(..f, ...)

departial(..f)
}
\arguments{
\item{..f}{Function.}

\item{...}{Argument values of \code{..f} to fix, specified by name or position.
Captured as \link[rlang:quotation]{quosures}.
\link[rlang:quasiquotation]{Unquoting} and \link[rlang:quasiquotation]{splicing}
are supported (see ‘Examples’).}
}
\value{
\code{partial()} returns a function whose \link[base:formals]{formals} are a
literal truncation of the formals of \code{..f()} (as a closure) by the fixed
arguments. \code{partial(..f)} is identical to \code{..f}.

In conformance with R’s calling convention, fixed argument values are lazy
\link[base:delayedAssign]{promises}. Moreover, when forced, they are \link[rlang:eval_tidy]{tidily
evaluated}. Lazy evaluation of fixed arguments can be
overridden via unquoting, see ‘Examples’.
}
\description{
\code{partial()} enables
\href{https://en.wikipedia.org/wiki/Partial_application}{partial application}:
given a function, it fixes the value of selected arguments to produce a
function of the remaining arguments.

\code{departial()} “inverts” the application of \code{partial()} by returning the
original function.
}
\details{
Even while \code{partial()} truncates formals, it remains compatible with
functions that use \code{\link[base:missing]{missing()}} to test whether a
specified argument was supplied in a call. For example,
\code{draw3 <- partial(sample, size = 3)} works as a function that randomly
draws three elements, even though \code{sample()} invokes \code{missing(size)} and
\code{draw3()} has signature \code{function (x, replace = FALSE, prob = NULL)}.

Because partially applied functions call the original function in an ad hoc
environment, impure functions that depend on the calling context as a
\emph{value}, rather than as a lexical scope, may not be amenable to
\code{partial()}. For example, \code{partial(ls, all.names = TRUE)()} is not
equivalent to \code{ls(all.names = TRUE)}, because \code{ls()} inspects the calling
environment to produce its value, whereas \code{partial(ls, all.names = TRUE)()}
calls \code{ls(all.names = TRUE)} from an (ephemeral) execution environment.
}
\examples{
# Arguments can be fixed by name
draw3 <- partial(sample, size = 3)
draw3(letters)

# Arguments can be fixed by position
draw3 <- partial(sample, , 3)
draw3(letters)

# Use departial() to recover the original function
stopifnot(identical(departial(draw3), sample))

# Lazily evaluate argument values by default
# The value of 'n' is evaluated whenever rnd() is called.
rnd <- partial(runif, n = rpois(1, 5))
replicate(4, rnd(), simplify = FALSE)   # variable length

# Eagerly evaluate argument values with unquoting (`!!`)
# The value of 'n' is fixed when 'rnd_eager' is created.
rnd_eager <- partial(runif, n = !!rpois(1, 5))
len <- length(rnd_eager())
reps <- replicate(4, rnd_eager(), simplify = FALSE)   # constant length
stopifnot(all(vapply(reps, length, integer(1)) == len))

# Mix evaluation schemes by combining lazy evaluation with unquoting (`!!`)
# Here 'n' is lazily evaluated, while 'max' is eagerly evaluated.
rnd_mixed <- partial(runif, n = rpois(1, 5), max = !!sample(10, 1))
replicate(4, rnd_mixed(), simplify = FALSE)

# Arguments to fix can be spliced
args_eager <- list(n = rpois(1, 5), max = sample(10, 1))
rnd_eager2 <- partial(runif, !!!args_eager)
replicate(4, rnd_eager2(), simplify = FALSE)

args_mixed <- rlang::exprs(n = rpois(1, 5), max = !!sample(10, 1))
rnd_mixed2 <- partial(runif, !!!args_mixed)
replicate(4, rnd_mixed2(), simplify = FALSE)

# partial() truncates formals by the fixed arguments
foo <- function(x, y = x, ..., z = "z") NULL
stopifnot(
  identical(
    formals(partial(foo)),
    formals(foo)
  ),
  identical(
    formals(partial(foo, x = 1)),
    formals(function(y = x, ..., z = "z") {})
  ),
  identical(
    formals(partial(foo, x = 1, y = 2)),
    formals(function(..., z = "z") {})
  ),
  identical(
    formals(partial(foo, x = 1, y = 2, z = 3)),
    formals(function(...) {})
  )
)

}
