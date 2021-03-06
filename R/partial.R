#' Fix a Number of Arguments to a Function
#'
#' @description
#' `partial()` enables
#' [partial application](https://en.wikipedia.org/wiki/Partial_application):
#' given a function, it fixes the value of selected arguments to produce a
#' function of the remaining arguments.
#'
#' `departial()` “inverts” the application of `partial()` by returning the
#' original function.
#'
#' @param ..f Function.
#' @param ... Argument values of `..f` to fix, specified by name or position.
#'   Captured as [quosures][rlang::quotation].
#'   [Unquoting][rlang::quasiquotation] and [splicing][rlang::quasiquotation]
#'   are supported (see ‘Examples’).
#'
#' @return `partial()` returns a function whose [formals][base::formals()] are a
#'   literal truncation of the formals of `..f()` (as a closure) by the fixed
#'   arguments. `partial(..f)` is identical to `..f`.
#'
#'   In conformance with R’s calling convention, fixed argument values are lazy
#'   [promises][base::delayedAssign()]. Moreover, when forced, they are [tidily
#'   evaluated][rlang::eval_tidy()]. Lazy evaluation of fixed arguments can be
#'   overridden via unquoting, see ‘Examples’.
#'
#' @details
#'   Even while `partial()` truncates formals, it remains compatible with
#'   functions that use [`missing()`][base::missing()] to test whether a
#'   specified argument was supplied in a call. For example,
#'   `draw3 <- partial(sample, size = 3)` works as a function that randomly
#'   draws three elements, even though `sample()` invokes `missing(size)` and
#'   `draw3()` has signature `function (x, replace = FALSE, prob = NULL)`.
#'
#'   Because partially applied functions call the original function in an ad hoc
#'   environment, impure functions that depend on the calling context as a
#'   _value_, rather than as a lexical scope, may not be amenable to
#'   `partial()`. For example, `partial(ls, all.names = TRUE)()` is not
#'   equivalent to `ls(all.names = TRUE)`, because `ls()` inspects the calling
#'   environment to produce its value, whereas `partial(ls, all.names = TRUE)()`
#'   calls `ls(all.names = TRUE)` from an (ephemeral) execution environment.
#'
#' @examples
#' # Arguments can be fixed by name
#' draw3 <- partial(sample, size = 3)
#' draw3(letters)
#'
#' # Arguments can be fixed by position
#' draw3 <- partial(sample, , 3)
#' draw3(letters)
#'
#' # Use departial() to recover the original function
#' stopifnot(identical(departial(draw3), sample))
#'
#' # Lazily evaluate argument values by default
#' # The value of 'n' is evaluated whenever rnd() is called.
#' rnd <- partial(runif, n = rpois(1, 5))
#' replicate(4, rnd(), simplify = FALSE)   # variable length
#'
#' # Eagerly evaluate argument values with unquoting (`!!`)
#' # The value of 'n' is fixed when 'rnd_eager' is created.
#' rnd_eager <- partial(runif, n = !!rpois(1, 5))
#' len <- length(rnd_eager())
#' reps <- replicate(4, rnd_eager(), simplify = FALSE)   # constant length
#' stopifnot(all(vapply(reps, length, integer(1)) == len))
#'
#' # Mix evaluation schemes by combining lazy evaluation with unquoting (`!!`)
#' # Here 'n' is lazily evaluated, while 'max' is eagerly evaluated.
#' rnd_mixed <- partial(runif, n = rpois(1, 5), max = !!sample(10, 1))
#' replicate(4, rnd_mixed(), simplify = FALSE)
#'
#' # Arguments to fix can be spliced
#' args_eager <- list(n = rpois(1, 5), max = sample(10, 1))
#' rnd_eager2 <- partial(runif, !!!args_eager)
#' replicate(4, rnd_eager2(), simplify = FALSE)
#'
#' args_mixed <- rlang::exprs(n = rpois(1, 5), max = !!sample(10, 1))
#' rnd_mixed2 <- partial(runif, !!!args_mixed)
#' replicate(4, rnd_mixed2(), simplify = FALSE)
#'
#' # partial() truncates formals by the fixed arguments
#' foo <- function(x, y = x, ..., z = "z") NULL
#' stopifnot(
#'   identical(
#'     formals(partial(foo)),
#'     formals(foo)
#'   ),
#'   identical(
#'     formals(partial(foo, x = 1)),
#'     formals(function(y = x, ..., z = "z") {})
#'   ),
#'   identical(
#'     formals(partial(foo, x = 1, y = 2)),
#'     formals(function(..., z = "z") {})
#'   ),
#'   identical(
#'     formals(partial(foo, x = 1, y = 2, z = 3)),
#'     formals(function(...) {})
#'   )
#' )
#'
#' @export
partial <- function(..f, ...) {
  UseMethod("partial")
}

#' @export
partial.default <- function(..f, ...) {
  not_fn_coercible(..f)
}

#' @export
partial.CompositeFunction <- function(..f, ...) {
  fst <- pipeline_head(..f)
  ..f[[fst$idx]] <- partial.function(fst$fn, ...)
  ..f
}

pipeline_head <- local({
  index_head <- function(x) {
    depth <- 0L
    while (is.list(x)) {
      depth <- depth + 1L
      x <- x[[1L]]
    }
    rep(1L, depth)
  }

  function(f) {
    fs <- as.list.CompositeFunction(f)
    idx <- index_head(fs)
    list(idx = idx, fn = fs[[idx]])
  }
})

#' @export
partial.function <- local({
  assign_setter("expr_partial")

  expr_fn <- function(..f, f) {
    expr <- substitute(..f, parent.frame())
    if (is.name(expr))
      return(expr)
    call("(", call("function", formals(f), quote(...)))
  }

  function(..f, ...) {
    if (missing(...))
      return(..f)
    f <- closure(..f)
    p <- partial_(f, ...)
    expr_partial(p) <- expr_partial(..f) %||% expr_fn(..f, f)
    class(p) <- "PartialFunction" %subclass% class(..f)
    p
  }
})

assign_getter("expr_partial")
assign_getter("names_fixed")

partial_ <- local({
  assign_getter("bare_args")
  assign_setter("bare_args")
  assign_setter("names_fixed")

  body <- quote({
    environment(`__partial__`) <- `__with_fixed_args__`()
    eval(`[[<-`(sys.call(), 1L, `__partial__`), parent.frame())
  })

  args <- function(f, nms) {
    bare_args(f) %||% eponymous(nms)
  }
  call_bare <- function(...) {
    as.call(c(quote(`__bare__`), ...))
  }

  no_name_reuse <- function(f, fix) {
    all(names(fix)[nzchar(names(fix))] %notin% names(names_fixed(f)))
  }

  function(f, ...) {
    fix <- quos_match(f, ...)
    f_bare <- departial.function(f)
    nms_bare <- names(formals(f_bare))
    if (has_dots(nms_bare)) {
      no_name_reuse(f, fix) %because% "Can't reset previously fixed argument(s)"
      nms_bare <- nms_bare[nms_bare != "..."]
      nms_priv <- privatize(names(fix), names_fixed(f))
      args_bare <- c(args(f, nms_bare), tidy_dots(nms_priv, nms_bare))
      body_bare <- call_bare(args_bare, quote(...))
    } else {
      nms_priv <- privatize(names(fix))
      args_bare <- args(f, nms_bare)
      body_bare <- call_bare(args_bare)
    }
    nms_fix <- c(nms_priv, names_fixed(f))
    fmls <- formals(f)[names(formals(f)) %notin% names(fix)]
    parent <- envir(f) %encloses% (fix %named% nms_priv)
    env_bare <- parent %encloses% list(`__bare__` = f_bare)
    env <- parent %encloses% list(
      `__with_fixed_args__` = promise_tidy(nms_fix, nms_bare, env_bare),
      `__partial__`         = new_fn(fmls, body_bare, env_bare)
    )
    p <- new_fn(fmls, body, env)
    names_fixed(p) <- nms_fix
    bare_args(p)   <- args_bare
    p
  }
})

quos_match <- local({
  non_void_expr <- function(q) {
    !identical(quo_get_expr(q), quote(expr = ))
  }

  function(..f, ...) {
    qs <- quos(...)
    ordered <- as.call(c(quote(c), seq_along(qs) %named% names(qs)))
    matched <- eval(match.call(..f, ordered), baseenv())
    qs <- qs %named% names_chr(matched)[order(matched)]
    qs[vapply(qs, non_void_expr, TRUE)]
  }
})

privatize <- local({
  privatize_ <- function(xs, nms = xs) {
    sprintf("..%s..", xs) %named% nms
  }
  n_dots <- function(x) {
    if (is.null(x))
      return(0L)
    sum(!nzchar(names(x)))
  }

  function(nms, nms_prev) {
    if (missing(nms_prev))
      return(privatize_(nms))
    nms_fill <- nms
    is_blank <- !nzchar(nms_fill)
    if ((n_blank <- sum(is_blank)) != 0L)
      nms_fill[is_blank] <- as.character(n_dots(nms_prev) + seq_len(n_blank))
    privatize_(nms_fill, nms)
  }
})

tidy_dots <- function(nms, nms_nondots) {
  dots <- nms[names(nms) %notin% nms_nondots]
  lapply(dots, eneval_tidy)
}

promise_tidy <- function(nms, nms_nondots, env) {
  nondots <- nms[names(nms) %in% nms_nondots]
  promises <- lapply(nondots, eneval_tidy)
  new_fn(promises, quote(environment()), env, eval_tidy = eval_tidy)
}

eneval_tidy <- function(nm) {
  call("eval_tidy", as.name(nm))
}

#' @rdname partial
#' @export
departial <- function(..f) {
  UseMethod("departial")
}

#' @export
departial.default <- function(..f) {
  not_fn_coercible(..f)
}

#' @export
departial.CompositeFunction <- function(..f) {
  fst <- pipeline_head(..f)
  ..f[[fst$idx]] <- departial.function(fst$fn)
  ..f
}

#' @export
departial.function <- local({
  get_bare    <- getter("__bare__")
  get_partial <- getter("__partial__")

  function(..f) {
    get_bare(get_partial(..f)) %||% ..f
  }
})

#' @export
print.PartialFunction <- function(x, ...) {
  cat("<Partially Applied Function>\n\n")
  expr_print(expr_partial_closure(x))
  cat("\nRecover the inner function with 'departial()'.")
  invisible(x)
}

expr_partial_closure <- local({
  get_partial_closure <- getter("__partial__")

  function(x) {
    make_expr <- get_partial_closure(x)
    environment(make_expr) <-
      environment(x) %encloses% list(`__bare__` = call_with_fixed_args(x))
    make_expr()
  }
})

call_with_fixed_args <- function(x) {
  formals_fixed <- function(env) {
    fmls <- formals(x)
    fmls <- lapply(fmls, function(arg) expr_uq(subst_called_args(arg), env))
    as.pairlist(fmls)
  }
  body_fixed <- function(call) {
    call <- subst_called_args(call)
    args <- lapply(call[-1L], subst_formal_args)
    as.call(c(expr_partial(x), args))
  }
  subst_called_args <- local({
    nms_fix <- names_fixed(x)
    nms_fix <- nms_fix[names(nms_fix) %in% names(formals(departial(x)))]
    exprs_fix <- lapply(nms_fix, function(nm) uq(as.name(nm)))

    function(expr) {
      do.call("substitute", list(expr, exprs_fix))
    }
  })

  function(...) {
    fmls_fixed <- formals_fixed(parent.frame())
    body_fixed <- body_fixed(sys.call())
    call_fixed <- call("function", fmls_fixed, call("{", body_fixed))
    expr_uq(call_fixed, parent.frame())
  }
}

subst_formal_args <- local({
  unquote <- list(eval_tidy = function(arg) uq(substitute(arg)))
  is_tidy_call <- check_head("eval_tidy")

  function(arg) {
    if (is.call(arg) && is_tidy_call(arg)) eval(arg, unquote) else arg
  }
})

expr_uq <- function(x, env) {
  eval(as.call(c(quote(rlang::expr), list(x))), env)
}

uq <- function(x) bquote(!!.(x))
