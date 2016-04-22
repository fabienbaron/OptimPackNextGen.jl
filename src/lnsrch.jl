#
# lnsrch.jl --
#
# Line search methods for TiPi.
#
#------------------------------------------------------------------------------
#
# This file is part of TiPi.jl licensed under the MIT "Expat" License.
#
# Copyright (C) 2015-2016, Éric Thiébaut.
#
#------------------------------------------------------------------------------

module LineSearch

export start!, iterate!, get_task, get_reason, get_step,
       AbstractLineSearch, BacktrackingLineSearch, MoreThuenteLineSearch

# Use the same floating point type for scalars as in TiPi.
import ..Float

# Common to all line search instances.
type CommonData
    step::Float            # current triel step
    finit::Float           # function value at step = 0
    ginit::Float           # derivative at step = 0
    stpmin::Float          # minimum step length
    stpmax::Float          # maximum step length
    reason::AbstractString # information message
    task::Symbol           # current pending task
    CommonData() = new(0, 0, 0, 0, 0, "", :START)
end

"""
## Line search methods

Line search methods are instances of types derived from the abstract type
`AbstractLineSearch`.  Assuming `SomeLineSearch` is a concrete line search
type, a typical line search is perfomred as follows:

    # Create an instance of the line search method:
    ls = SomeLineSearch(...)

    # Start the line search and loop until a step satisfying
    # some conditions is found:
    x0 = ...            # initial variables
    f0 = func(x)        # function value at x0
    g0 = grad(x)        # gradient at x0
    d = ...             # search direction
    dtg0 = inner(d, g0) # directional derivative at x0
    stp = ...           # initial step
    stpmin = ...        # lower bound for the step
    stpmax = ...        # upper bound for the step
    searching = start!(ls, stp, f0, dtg0, stpmin, stpmax)
    while searching
        x = x0 + stp*d    # compute trial point
        f = func(x)       # function value at x
        g = grad(x)       # gradient at x
        dtg = inner(d, g) # directional derivative at x
        stp, searching = iterate!(ls, stp, f, dtg)
    end
    task = get_task(ls)
    if task != :CONVERGENCE
        if task == :ERROR
            error(get_reason(ls))
        else
            warn(get_reason(ls))
        end
    end

"""
abstract AbstractLineSearch

"""
`get_task(ls)` yields the current pending task for the line search instance
`ls`.  The result is one of the following symbols:

* `:START` if line search `ls` has not yet been started with `start!(ls, ...)`.

* `:SEARCH` if line search `ls` is in progress; the caller shall compute the
  value of the function and its derivative at the current trial step and call
  `iterate!(ls, ...)`.

* `:CONVERGENCE` if line search `ls` has converged.

* `:WARNING` if line search `ls` has been stopped with a warning; use
  `get_reason(ls)` to retrieve a textual explanation.

* `:ERROR` if there are any errors; use `get_reason(ls)` to retrieve a textual
  error message.
"""
get_task(ls::AbstractLineSearch) = ls.base.task

"""
`get_step(ls)` yields the current trial step for the line search instance `ls`.
"""
get_step(ls::AbstractLineSearch) = ls.base.step


"""
`get_reason(ls)` yields the error or warning message for the line search
instance `ls`.
"""
get_reason(ls::AbstractLineSearch) = ls.base.reason

"""
`requires_derivative(ls)` indicates whether the line search instance `ls`
requires the derivative of the function when calling `iterate!`.  Alternatively
`ls` can also be the line search type.  Note that the derivative is always
needed by the `start!` method.
"""
requires_derivative{T<:AbstractLineSearch}(::T) = requires_derivative(T)

"""
A line search is started by:

    search = start!(ls, stp, f0, g0, stpmin, stpmax)

which returns a boolean `search` indicating whether to try `stp` as the first
step.  If `search` is true then the caller shall compute the value of the
function and its derivative at the setp `stp` and call `iterate!`

Arguments are:

* `stp` is a positive initial estimate of the next step to take.

* `f0` is the value of the function at 0.

* `g0` is the derivative of the function at 0.

* `stpmin` is a nonnegative lower bound for the step.

* `stpmax` is a nonnegative upper bound for the step.

* `search` is a boolean indicating whether to try `stp` as the first step.

"""
function start!(ls::AbstractLineSearch, stp::Real, f0::Real, g0::Real,
                stpmin::Real, stpmax::Real)
    start!(ls, Float(stp), Float(f0), Float(g0), Float(stpmin), Float(stpmax))
    #error("`start!` method not implemented for this line search method")
end

"""
The call:

    (stp, search) = iterate!(ls, stp, f, g)

performs next line search iteration and return the next trial step `stp` and a
boolean `search` indicating whether to continue searching.  If `search` is true
then the caller shall compute the value of the function and its derivative for
the output value `stp` of the step and call `iterate!` again.  Otherwise, the
line search is terminated (the value of `stp` is left unchanged) either because
of convergence, failure or warnings.

Arguments are:

* `stp` is the current estimate of a satisfactory step.

* `f` is the value of the function at 0.

* `g` is the derivative of the function at 0.

"""
function iterate!(ls::AbstractLineSearch, stp::Real, f::Real, g::Real)
    iterate!(ls, Float(stp), Float(f), Float(g))
    #error("`iterate!` method not implemented for this line search method")
end

# Private method to check and instanciate common parameters when starting a new
# line search.
function start!(ws::CommonData, stp::Float, f0::Float, g0::Float,
                stpmin::Float, stpmax::Float)
    @assert 0 ≤ stpmin ≤ stpmax
    @assert stpmin ≤ stp ≤ stpmax
    @assert g0 < 0 "not a descent direction"
    ws.step = stp
    ws.finit = f0
    ws.ginit = g0
    ws.stpmin = stpmin
    ws.stpmax = stpmax
    ws.reason = ""
    ws.task = :SEARCH
end

# Private method to provide the next trial step.
function searching!(ws::CommonData, stp::Float)
    ws.step = stp
    ws.task = :SEARCH
    ws.reason = ""
    return (ws.step, true)
end

# Private method to indicate that the line search has converged.
function convergence!(ws::CommonData, reason::AbstractString)
    ws.task = :CONVERGENCE
    ws.reason = reason
    return (ws.step, false)
end

# Private method to indicate that the line search is terminated with a warning.
function warning!(ws::CommonData, reason::AbstractString)
    ws.task = :WARNING
    ws.reason = reason
    return (ws.step, false)
end

# Private method to indicate that the line search has failed for some reason.
function failure!(ws::CommonData, reason::AbstractString)
    ws.task = :ERROR
    ws.reason = reason
    return (ws.step, false)
end

#------------------------------------------------------------------------------
"""
## Backtracking and Armijo line search methods

The call:

    ls = BacktrackingLineSearch(ftol=..., amin=...)

yields a line search method finds a step that satisfies the sufficient decrease
condition:

    f(stp) ≤ f(0) + ftol*stp*f'(0),

where `stp` is smaller or equal the initial step (backtracking).

Possible keywords are:

* `ftol` specifies a nonnegative tolerance for the sufficient decrease
         condition.

* `amin` specifies a minimal relative step size to trigger taking a bisection
  step instead of a quadratic step; if `amin ≥ 1/2`, a bisection step is always
  taken which amounts to Armijo's method.

Default values are `ftol = 1e-3` and `amin = 1/2`.

"""
type BacktrackingLineSearch <: AbstractLineSearch

    # Common to all line search instances.
    base::CommonData

    # Specific parameters.
    ftol::Float
    amin::Float
    gtest::Float

    # Constructor.
    function BacktrackingLineSearch(;
                                    ftol::Float=1e-3,
                                    amin::Float=0.5)
        @assert ftol ≥ 0
        @assert amin ≥ 0
        new(CommonData(), ftol, amin, 0)
    end
end

requires_derivative(::Type{BacktrackingLineSearch}) = false

function start!(ls::BacktrackingLineSearch, stp::Float, f0::Float, g0::Float,
                stpmin::Float, stpmax::Float)
    start!(ls.base, stp, f0, g0, stpmin, stpmax)
    ls.gtest = ls.ftol*ls.base.ginit
    return true
end

function iterate!(ls::BacktrackingLineSearch, stp::Float, f::Float, g::Float)
    const HALF = Float(1)/Float(2)

    # Check for convergence otherwise take a (safeguarded) bisection
    # step unless already at the lower bound.
    if f ≤ ls.base.finit + stp*ls.gtest
        # First Wolfe (Armijo) condition satisfied.
        return convergence!(ls.base, "Armijo's condition holds")
    end
    if stp ≤ ls.base.stpmin
        stp = ls.base.stpmin
        return warning!(ls.base, "stp ≤ stpmin")
    end
    if ls.amin ≥ HALF
        # Bisection step.
        stp *= HALF
    else
        q::Float = -stp*ls.base.ginit;
        r::Float = (f - (ls.base.finit - q))*Float(2)
        if r ≤ 0
            # Bisection step.
            stp *= HALF
        elseif q ≤ ls.amin*r
            # Small step.
            stp *= ls.amin
        else
            # Quadratic step.
            stp *= q/r
        end
    end
    if stp < ls.base.stpmin
        # Safeguard the step.
        stp = ls.base.stpmin
    end

    # Obtain another function and derivative.
    return searching!(ls.base, stp)

end

#------------------------------------------------------------------------------
"""
## Moré & Thuente line search method

Moré & Thuente line search method finds a step that satisfies a sufficient
decrease condition and a curvature condition.

The algorithm is designed to find a step `stp` that satisfies the sufficient
decrease condition:

      f(stp) ≤ f(0) + ftol*stp*f'(0),

and the curvature condition:

      abs(f'(stp)) ≤ gtol*abs(f'(0)).

If `ftol` is less than `gtol` and if, for example, the function is bounded
below, then there is always a step which satisfies both conditions.

Each call to `iterate!` updates an interval with endpoints `stx` and `sty`.
The interval is initially chosen so that it contains a minimizer of the
modified function:

      psi(stp) = f(stp) - f(0) - ftol*stp*f'(0).

If `psi(stp) ≤ 0` and `f'(stp) ≥ 0` for some step `stp`, then the interval is
chosen so that it contains a minimizer of `f`.

If no step can be found that satisfies both conditions, then the algorithm
stops with a warning.  In this case `stp` only satisfies the sufficient
decrease condition.

The line search instance is created by:

    ls = MoreThuenteLineSearch(ftol=..., gtol=..., xtol=...)

where:

* `ftol` specifies a nonnegative tolerance for the sufficient decrease
         condition.

* `gtol` specifies a nonnegative tolerance for the curvature condition.

* `xtol` specifies a nonnegative relative tolerance for an acceptable step. The
         subroutine exits with a warning if the relative difference between
         `sty` and `stx` is less than `xtol`.

Default values for these parameters are `ftol=1e-3`, `gtol=0.9` and xtol=0.1
which are suitable for quasi Newton line search.


### References

* Moré, J. J. & Thuente, D. J. "Line search algorithms with guaranteed
  sufficient decrease", ACM Trans. Math. Softw., ACM Press, vol. 20,
  pp. 286-307 (1994).


### History

* MINPACK-1 Project. June 1983.  Argonne National Laboratory.  Jorge J. Moré
   and David J. Thuente.

* MINPACK-2 Project. November 1993.  Argonne National Laboratory and University
  of Minnesota.  Brett M. Averick, Richard G. Carter, and Jorge J. Moré.

* TiPi.jl Project.  April 2016.  Centre de Recherche Astrophysique de Lyon.
  Conversion to Julia by Éric Thiébaut.

"""
type MoreThuenteLineSearch <: AbstractLineSearch

    # Common to all line search instances.
    base::CommonData

    # Specific parameters.
    ftol::Float
    gtol::Float
    xtol::Float
    gtest::Float
    width::Float
    width1::Float
    stage::Int

    # Parameters shared with `cstep!`.
    #
    # The members `stx`, `fx`, `dx` contain the values of the step,
    # function, and derivative at the best step.
    #
    # The members `sty`, `fy`, `dy` contain the value of the step,
    # function, and derivative at `sty`.
    #
    smin::Float # minimum step in cstep!
    smax::Float # maximum step in cstep!
    stx::Float
    fx::Float
    dx::Float
    sty::Float
    fy::Float
    dy::Float
    brackt::Bool

    function MoreThuenteLineSearch(;
                                  ftol::Float=1e-3,
                                  gtol::Float=0.9,
                                  xtol::Float=0.1)
        @assert ftol ≥ 0
        @assert gtol ≥ 0
        @assert xtol ≥ 0

        ls = new(CommonData())

        ls.ftol = ftol
        ls.gtol = gtol
        ls.xtol = xtol
        ls.gtest = 0
        ls.width = 0
        ls.width1 = 0
        ls.stage = 0

        ls.smin = 0
        ls.smax = 0
        ls.stx = 0
        ls.fx = 0
        ls.dx = 0
        ls.sty = 0
        ls.fy = 0
        ls.dy = 0
        ls.brackt = false
        return ls
    end
end

requires_derivative(::Type{MoreThuenteLineSearch}) = true

const xtrapl = Float(1.1)
const xtrapu = Float(4.0)

# The arguments `stp`, `f`, `g` contain the values of the step,
# function, and directional derivative at `stp`.
function start!(ls::MoreThuenteLineSearch, stp::Float, f0::Float, g0::Float,
                stpmin::Float, stpmax::Float)
    start!(ls.base, stp, f0, g0, stpmin, stpmax)
    ls.brackt = false
    ls.stage = 1
    ls.gtest = ls.ftol*ls.base.ginit
    ls.width = ls.base.stpmax - ls.base.stpmin
    ls.width1 = 2*ls.width
    ls.stx = 0
    ls.fx = ls.base.finit
    ls.dx = ls.base.ginit
    ls.sty = 0
    ls.fy = ls.base.finit
    ls.dy = ls.base.ginit
    ls.smin = 0
    ls.smax = stp + xtrapu*stp
    return true

end

function iterate!(ls::MoreThuenteLineSearch, stp::Float, f::Float, g::Float)
    # If psi(stp) ≤ 0 and f'(stp) ≥ 0 for some step, then the algorithm
    # enters the second stage.
    ftest::Float = ls.base.finit + stp*ls.gtest
    if ls.stage == 1 && f ≤ ftest && g ≥ 0
        ls.stage = 2
    end

    # Test for termination (convergence or warnings).
    if f ≤ ftest && abs(g) ≤ -ls.gtol*ls.base.ginit
        return convergence!(ls.base, "strong Wolfe conditions hold")
    elseif stp == ls.base.stpmin && (f > ftest || g ≥ ls.gtest)
        return warning!(ls.base, "stp = stpmin")
    elseif stp == ls.base.stpmax && f ≤ ftest && g ≤ ls.gtest
        return warning!(ls.base, "stp = stpmax")
    elseif ls.brackt && ls.smax - ls.smin ≤ ls.xtol*ls.smax
        return warning!(ls.base, "xtol test satisfied")
    elseif ls.brackt && (stp ≤ ls.smin || stp ≥ ls.smax)
        return warning!(ls.base, "rounding errors prevent progress")
    end

    # A modified function is used to predict the step during the first stage
    # if a lower function value has been obtained but the decrease is not
    # sufficient.

    if ls.stage == 1 && f ≤ ls.fx && f > ftest

        # Define the modified function and derivative values.
        ls.fx -= ls.stx*ls.gtest
        ls.fy -= ls.sty*ls.gtest
        ls.dx -= ls.gtest
        ls.dy -= ls.gtest

        # Call `cstep!` to update `stx`, `sty`, and to compute the new step.
        stp = cstep!(ls, stp, f - stp*ls.gtest, g - ls.gtest)

        # Reset the function and derivative values for f.
        ls.fx += ls.stx*ls.gtest
        ls.fy += ls.sty*ls.gtest
        ls.dx += ls.gtest
        ls.dy += ls.gtest

    else

        # Call `cstep!` to update `stx`, `sty`, and to compute the new step.
        stp = cstep!(ls, stp, f, g)

    end

    # Decide if a bisection step is needed.
    if ls.brackt
        if (abs(ls.sty - ls.stx) ≥ 0.66*ls.width1)
            stp = ls.stx + 0.5*(ls.sty - ls.stx)
        end
        ls.width1 = ls.width
        ls.width = abs(ls.sty - ls.stx)
    end

    # Set the minimum and maximum steps allowed for `stp`.
    if ls.brackt
        ls.smin = min(ls.stx, ls.sty)
        ls.smax = max(ls.stx, ls.sty)
    else
        ls.smin = stp + xtrapl*(stp - ls.stx)
        ls.smax = stp + xtrapu*(stp - ls.stx)
    end

    # Force the step to be within the bounds `stpmax` and `stpmin`.
    stp = max(stp, ls.base.stpmin)
    stp = min(stp, ls.base.stpmax)

    # If further progress is not possible, let `stp` be the best point
    # obtained during the search.

    if (ls.brackt && (stp ≤ ls.smin || stp ≥ ls.smax) ||
        (ls.brackt && ls.smax - ls.smin ≤ ls.xtol*ls.smax))
        stp = ls.stx
    end

    # Obtain another function and derivative.
    return searching!(ls.base, stp)

end

"""
## Compute a safeguarded cubic step

The call:

     nextstep = cstep!(ls, stp, fp, dp)

computes a safeguarded step for a search procedure and updates an interval that
contains a step that satisfies a sufficient decrease and a curvature condition.

The argument `stp` is the current step, the argument `fp` and `dp` respectively
give the function value and derivative at `stp`.  The returned value `nextstep`
is the new trial step.

The parameter `ls.stx` contains the step with the least function value.  If
`ls.brackt` is set to true then a minimizer has been bracketed in an interval
with endpoints `ls.stx` and `ls.sty`.  The subroutine assumes that if
`ls.brackt` is set to true then:

    min(ls.stx, ls.sty) < stp < max(ls.stx, ls.sty),

and that the derivative at `stx` is negative in the direction of the step.

Workspace `ls` is used as follows:

* `ls.stx` is the best step obtained so far and is an endpoint of the interval
  that contains the minimizer.  On exit, `ls.stx` is the updated best step.

* `ls.fx` is the function value at `ls.stx`.  On exit, `ls.fx` is the updated
  function value at `ls.stx`.

* `ls.dx` is derivative of the function at `ls.stx`.  The derivative must be
  negative in the direction of the step, that is, `ls.dx` and `stp - ls.stx`
  must have opposite signs.  On exit, `ls.dx` is the updated derivative of the
  function at `ls.stx`.

* `ls.sty` is the second endpoint of the interval that contains the minimizer.
  On exit, `ls.sty` is the updated endpoint of the interval that contains the
  minimizer.

* `ls.fy` is the function value at `ls.sty`.  On exit, `ls.fy` is the updated
  function value at `ls.sty`.

* `ls.dy` is derivative of the function at `ls.sty`.  On exit, `ls.dy` is the
  updated derivative of the function at `ls.sty`.

* `ls.brackt` is a boolean variable which specifies if a minimizer has been
  bracketed.  Initially `ls.brackt` must be set to `false`.  On exit,
  `ls.brackt` specifies if a minimizer has been bracketed.

* `ls.smin` is a lower bound for the step.  Its value is left unchanged.

* `ls.smax` is an upper bound for the step.  Its value is left unchanged.


### History

* MINPACK-1 Project.  June 1983.  Argonne National Laboratory.
  Jorge J. Moré and David J. Thuente.

* MINPACK-2 Project.  November 1993.  Argonne National Laboratory and
  University of Minnesota.  Brett M. Averick and Jorge J. Moré.

* TiPi.jl Project.  April 2016.  Centre de Recherche Astrophysique de Lyon.
  Conversion to Julia by Éric Thiébaut.

"""
function cstep!(ls::MoreThuenteLineSearch, stp::Float, fp::Float, dp::Float)

    const ZERO::Float = 0
    const TWO::Float = 2
    const THREE::Float = 3
    const P66::Float = 0.66

    stx::Float = ls.stx
    fx::Float  = ls.fx
    dx::Float  = ls.dx
    sty::Float = ls.sty
    fy::Float  = ls.fy
    dy::Float  = ls.dy
    stpmin::Float = ls.smin
    stpmax::Float = ls.smax

    opposite = (dx < ZERO < dp) || (dp < ZERO < dx)

    if fp > fx

        # First case: A higher function value.  The minimum is bracketed.  If
        # the cubic step is closer to `stx` than the quadratic step, the cubic
        # step is taken, otherwise the average of the cubic and quadratic steps
        # is taken.

        theta = THREE*(fx - fp)/(stp - stx) + dx + dp
        s = max(abs(theta), abs(dx), abs(dp))
        gamma = s*sqrt((theta/s)^2 - (dx/s)*(dp/s))
        if stp < stx; gamma = -gamma; end
        p = (gamma - dx) + theta
        q = ((gamma - dx) + gamma) + dp
        r = p/q
        stpc = stx + r*(stp - stx)
        stpq = stx + ((dx/((fx - fp)/(stp - stx) + dx))/TWO)*(stp - stx)
        if abs(stpc - stx) < abs(stpq - stx)
            stpf = stpc
        else
            stpf = stpc + (stpq - stpc)/TWO
        end
        ls.brackt = true

    elseif opposite

        # Second case: A lower function value and derivatives of opposite sign.
        # The minimum is bracketed.  If the cubic step is farther from `stp`
        # than the secant step, the cubic step is taken, otherwise the secant
        # step is taken.

        theta = THREE*(fx - fp)/(stp - stx) + dx + dp
        s = max(abs(theta), abs(dx), abs(dp))
        gamma = s*sqrt((theta/s)^2 - (dx/s)*(dp/s))
        if stp > stx; gamma = -gamma; end
        p = (gamma - dp) + theta
        q = ((gamma - dp) + gamma) + dx
        r = p/q
        stpc = stp + r*(stx - stp)
        stpq = stp + (dp/(dp - dx))*(stx - stp)
        if abs(stpc - stp) > abs(stpq - stp)
            stpf = stpc
        else
            stpf = stpq
        end
        ls.brackt = true

      elseif abs(dp) < abs(dx)

        # Third case: A lower function value, derivatives of the same sign, and
        # the magnitude of the derivative decreases.
        #
        # The cubic step is computed only if the cubic tends to infinity in the
        # direction of the step or if the minimum of the cubic is beyond
        # stp. Otherwise the cubic step is defined to be the secant step.

        theta = THREE*(fx - fp)/(stp - stx) + dx + dp
        s = max(abs(theta), abs(dx), abs(dp))

        # The case `gamma = 0` only arises if the cubic does not tend to
        # infinity in the direction of the step.

        gamma = s*sqrt(max(ZERO, (theta/s)^2 - (dx/s)*(dp/s)))
        if stp > stx; gamma = -gamma; end
        p = (gamma - dp) + theta
        q = (gamma + (dx - dp)) + gamma
        r = p/q
        if r < ZERO && gamma != ZERO
            stpc = stp + r*(stx - stp)
        elseif stp > stx
            stpc = stpmax
        else
            stpc = stpmin
        end
        stpq = stp + (dp/(dp - dx))*(stx - stp)

        if ls.brackt

            # A minimizer has been bracketed.  If the cubic step is closer to
            # `stp` than the secant step, the cubic step is taken, otherwise
            # the secant step is taken.

            if abs(stpc - stp) < abs(stpq - stp)
               stpf = stpc
            else
               stpf = stpq
            end
            if stp > stx
               stpf = min(stp + P66*(sty - stp), stpf)
            else
               stpf = max(stp + P66*(sty - stp), stpf)
            end

         else

            # A minimizer has not been bracketed.  If the cubic step is farther
            # from `stp` than the secant step, the cubic step is taken,
            # otherwise the secant step is taken.

            if abs(stpc - stp) > abs(stpq - stp)
               stpf = stpc
            else
               stpf = stpq
            end
            stpf = min(stpmax, stpf)
            stpf = max(stpmin, stpf)

         end

    else

        # Fourth case: A lower function value, derivatives of the same sign,
        # and the magnitude of the derivative does not decrease.  If the
        # minimum is not bracketed, the step is either `stpmin` or `stpmax`,
        # otherwise the cubic step is taken.

        if ls.brackt
            theta = THREE*(fp - fy)/(sty - stp) + dy + dp
            s = max(abs(theta), abs(dy), abs(dp))
            gamma = s*sqrt((theta/s)^2-(dy/s)*(dp/s))
            if stp > sty; gamma = -gamma; end
            p = (gamma - dp) + theta
            q = ((gamma - dp) + gamma) + dy
            r = p/q
            stpc = stp + r*(sty - stp)
            stpf = stpc
        elseif stp > stx
            stpf = stpmax
        else
            stpf = stpmin
        end
    end

    # Update the interval which contains a minimizer.
    if fp > fx
        ls.sty = stp
        ls.fy = fp
        ls.dy = dp
    else
        if opposite
            ls.sty = stx
            ls.fy = fx
            ls.dy = dx
        end
        ls.stx = stp
        ls.fx = fp
        ls.dx = dp
    end

    # Return the new step.
    return stpf

end

end # module
