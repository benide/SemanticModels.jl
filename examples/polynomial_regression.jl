# -*- coding: utf-8 -*-
# # Univariate Polynomial Regression
#
# This example demonstrates how to use manipulate a univariate regression model in an algebraically precise way. It builds on the example `pseudo_polynomial_regression.jl`.

# Let `m` be a statistical model like 
# ```julia
# f(x) = βx
# X = rand(Normal(0,1), n)
# target[i] = f(X[i]) + rand(Normal(0,1), 1)
# min_{a,b} sum_i (f(X[i]) - target[i])^2
# ```
#
# So it is a linear least squares regression model. The parameter $\beta$ is the regression coefficients that are learned from data.
#
# Define the set of transformations $T$ as the free monoid generated by
#
# ```julia
# T_x = f(x)->x*f(x)
# T_1 = f(x)->f(x) + C
# ```
#
# Namely, the set of strings over the alphabet $\{T_x, T_1\}$
#
# The monoid generated by this set of transformations acts on `m` to create all polynomial univariate regressions.
#
# ```julia
# f(x) = sum(β_i*x^i)
# X = rand(Normal(0,1), n)
# target[i] = f(X[i]) + rand(Normal(0,1), 1)
# min_{β} sum_i (f_β(x[i]) - target[i])^2
# ```
#
# for all polynomials `f`. The ring of polynomials is well studied and we should be able to apply our knowledge of polynomial algebras to say something about the model transformations.
#
# We will  replicate the feature selection process used in standard polynomial regression models using our model augmentation tools.
#
# Here is an example implementation of this theory.

# ## Example Model

#Our working example of a multivariate nonlinear regression model
expr = quote
    module Regression
    using Random
    using LsqFit
    using LinearAlgebra

    function f(x, β)
        # This .+ node is added so that we have something to grab onto
        # in the metaprogramming. It is the ∀a .+(a) == a. 
        return .+(β[1].* x.^0)
    end
    # Generate the data for this example
    function sample(g::Function, n)
        x = randn(Float64, n)
        target = g(x) .+ randn(Float64, n[1])./1600
        return x, target
    end
    
    # Compute the regression statistics
    function describe(fit)
        if !fit.converged
            error("Did not converge")
        end
        return (β = fit.param, r=norm(fit.resid,2), n=length(fit.resid))
    end
    #setup

    # Random.seed!(42)
    β = (1/2, 1/2)
    n = (1000)
    g(x) = β[1].*x.^3 + β[2].*x.^2
    X, target = sample(g, n)
    # x, y = X[:,1], X[:,2]
    # @show size(X), size(target)
    # loss(a) = sum((f.(a, x, y) .- target).^2)
    # @show loss.([-1,-1/2,-1/4, 0, 1/4,1/3,1/2,2/3, 1])

    a₀ = [1.5]
    try
        ŷ₀ = f(X, a₀)
        catch except
        @show except
        error("Could not execute f on the initial data")
    end

    #solving
    fit = curve_fit(f, X, target, a₀)#; autodiff=:forwarddiff)
    result = describe(fit)
    end
end
eval(expr.args[2])
Regression.fit.param

# ## Implementation Details
# The following code is the implementation details for representing the models as an `AbstractProblem` and representing the transformations as sequences of operations and applying the transformations onto the models.
#
# You can skip these if you are not interested in how this is implemented.

# +
using LinearAlgebra
import Base: show

using SemanticModels
using SemanticModels.ModelTools
import SemanticModels.ModelTools: model, AbstractModel, isexpr
import SemanticModels.ModelTools.Transformations: Pow
import SemanticModels.Parsers: findfunc, findassign
# -

ModelTools.Transformations.Pow

# +
"""    Lsq


A program that solves min_β || f(X,β) - y ||_2

Example:

`f(X, β) = β[1].*X.^p .+ β[2].*X.^q`

See also [`(t::Pow)(m::Lsq)`](@ref)
"""
struct Lsq <: AbstractModel
    expr
    f
    coefficient
    p₀
end

function show(io::IO, m::Lsq)
    write(io, "Lsq(\n  f=$(repr(m.f)),\n  coefficient=$(repr(m.coefficient)),\n  p₀=$(repr(m.p₀))\n)")
end

function model(::Type{Lsq}, expr::Expr)
    if expr.head == :block
        return model(Lsq, expr.args[2])
    end
    objective = :l2norm
    f = callsites(expr, :curve_fit)[end].args[2]
    coeff = callsites(expr, f)[1].args[end]
    p₀ = callsites(expr, :curve_fit)[end].args[end]
    return Lsq(expr, f, coeff, p₀)
end

"""    poly(m::Lsq)::Expr

find the part of the model that implements the polynomial model for regression.
"""
function poly(m::Lsq)
    func = findfunc(m.expr, m.f)[1]
    poly = func.args[2].args[end].args[1]
    return poly
end

"""    (t::Pow)(m::Lsq)

Example:

If `m` is a program implementing `f(X, β) = β[1]*X^p + β[2]*X^q`

a) and `t = Pow(2)` then `t(m)` is the model implementing
`f(X, β) = β[1]*X^p+2 + β[2]*X^q+q`.

"""
function (t::Pow)(m::Lsq)
    p = poly(m)
    for i in 2:length(p.args)
        slot = p.args[i]
        pow = callsites(slot, :(.^))
        pow[end].args[3] += t.inc
    end
    return m
end

struct AddConst <: ModelTools.Transformations.Transformation end

"""    (c::AddConst)(m::Lsq)

Example:

If `m` is a program implementing `f(X, β) = β[1]*X^p + β[2]*X^q`

a) and `c = AddConst()` then `c(m)` is the model implementing
`f(X, β) = β[1]*X^p + β[2]*X^0`.

"""
function (c::AddConst)(m::Lsq)
    p = poly(m)
    ix = map(t->t.args[2].args[2], p.args[2:end])
    i = maximum(ix)+1
    @show p
    push!(p.args, :(β[$i].*x.^0))
    assigns = findassign(m.expr, m.p₀)
    @show assigns
    b = assigns[end].args[2].args
    push!(b, 1)
    return m
end
# -

m = model(Lsq, deepcopy(expr))

# ## Model Augmentation with Group Actions
#
# Now we have all the machinery in place to build novel models from old models.

# Let's build an instance of the model object from the code snippet expr
m = model(Lsq, deepcopy(expr))
@show m
poly(m)

# Some *generator elements* will come in handy for building elements of the transformation group.
# $T_x,T_1$ are *generators* for our group of transformations $T = \langle T_x, T_1 \rangle$. Application of $T_1$ adds a constant to our polynomial while application of $T_x$ increments all the powers of the terms by 1. Any polynomial can be generated by these two operations. 

@show Tₓ = Pow(1)
@show T₁ = AddConst()
Tₓ, T₁

# TODO: make these tests

m = model(Lsq, deepcopy(expr))
@show poly(Tₓ(m))
@show poly(T₁(m))
@show poly(Tₓ(m))
@show poly(Tₓ(m))
@show poly(T₁(m))

# Theorem: Any polynomial regression model can be produced by repeated application of $T_x,T_1$. 
#
# Proof: Let $p(x) = \sum_i^d \beta_i x^i$ Starting from $q_0(x)= \beta[1] = \beta[1] x^0$, 
#
# ```
# for i in 1:d
#    if \beta_{d-i} != 0 then 
#       apply T_1
#    end
#    apply T_x
# end
# ```
#
# This algorithm is Horner's rule for evaluating $p(x)$ on the symbolic coeffients $\beta_i$

# ## Exploring the Orbits
#
# We use the Levenberg Marquardt algorithm for general least squares problems in data analysis. The goal is to fix a model class and find the best coefficients for that class. Our algebraic representation allows us to have a similar treatment of model class (in this case the exponents $i,j$ in our formula). We can sample from the orbits of the group when applied to the model and solve for the best coefficients in order to find the best model class.
#
# In this case we have reduced the code search space to a model search space to an algebraic formulation.

m = model(Lsq, deepcopy(expr))
results = []
for i in 1:5
    p = poly(m)
    M = eval(m.expr)
    push!(results, (i=i, M.result..., p=deepcopy(p)))
    T₁(Tₓ(m))
end


# It turns out that this method recovers the *true* model order $2,3$

for r in results
    # \t$(map(x->string(x.args[3]), r.p.args[2:end]))
    β̂ = map(βᵢ -> round(βᵢ, digits=4), r.β)
    s = join(map(x->string(x.args[3].args[3]), r.p.args[2:end]),", ")
    dof = length(r.p.args)-1
    println("DoF: $(dof)\tPoly: x^{$s}")
    println("Residual: $(round(r.r, digits=4))\tβ̂: $(β̂))")
    ℓ1 = norm(β̂, 1)
    println("ℓ₁ norm of β̂: $ℓ1")
    println("--------------------------------------------------------\n\n")
end


# ## Appied Algebra
#
# We know that the data generating function is an odd polynomial and that any polynomial in $\langle T_x\dot T_x, T_1\rangle$ will be even. The following metamodel shows that no even polynomial fits our data well. 

# +
m = model(Lsq, deepcopy(expr))
results = []
for i in 1:5
    p = poly(m)
    M = eval(m.expr)
    push!(results, (i=i, M.result..., p=deepcopy(p)))
    T₁(Tₓ(Tₓ(m)))
end
 
for r in results
    # \t$(map(x->string(x.args[3]), r.p.args[2:end]))
    β̂ = map(βᵢ -> round(βᵢ, digits=4), r.β)
    s = join(map(x->string(x.args[3].args[3]), r.p.args[2:end]),", ")
    dof = length(r.p.args)-1
    println("DoF: $(dof)\tPoly: x^{$s}")
    println("Residual: $(round(r.r, digits=4))\tβ̂: $(β̂))")
    ℓ1 = norm(β̂, 1)
    println("ℓ₁ norm of β̂: $ℓ1")
    println("--------------------------------------------------------\n\n")
end
# -


# ## Conclusions
#
# We have seen how abstract algebra can be applied to the category of models to build a systematic treatment of model augmentation. This proves that the model transformations can be arranged into a simple algebraic structure that can act on a model to build new models. The structure of the transformations are easier to analyze than the changes to the models themselves. 
