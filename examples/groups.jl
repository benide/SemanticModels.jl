module Transformations
using SemanticModels.Parsers
using SemanticModels.ModelTools
import Base: ∘, show, convert, promote
import SemanticModels.ModelTools: AbstractProblem, model

export Transformation, ConcatTransformation, Product, Pow, MonomialRegression

postwalk(f, x) = walk(x, x -> postwalk(f, x), f)

abstract type Transformation end

struct ConcatTransformation
    seq::Vector{Transformation}
end

promote(a::ConcatTransformation, b::Transformation) = (a, ConcatTransformation([b]))
convert(::ConcatTransformation, t::Transformation) = ConcatTransformation([t])

function ∘(f::ConcatTransformation, g::ConcatTransformation)
    append!(g.seq, f.seq)
    return g
end

function (f::ConcatTransformation)(m::AbstractProblem)
    return foldl((m, t)->t(m), [m; f.seq])
end

struct Pow{T} <: Transformation
    inc::T
end

∘(p::Pow, q::Pow) = Pow(p.inc + q.inc)

struct Product{T} <: Transformation
    dims::T
end

function (f::Product)(m::AbstractProblem)
    return foldl((m, t)->t(m), [m; f.dims])
end

∘(p::Transformation, args...) = ∘(promote(p, args...)...)
∘(p::Product, q::Product) = Product(p.dims .∘ q.dims)

promote(p::Product{T}, t::T) where T= (p, Product(t))
pd = Product((Pow(1),Pow(2))) ∘ (Pow(1),Pow(2))

struct MonomialRegression <: AbstractProblem
    expr
    f
    coefficient
    objective
    interval
end

function funcarg(ex::Expr)
    return ex.args[1].args[2]
end

isexpr(x) = isa(x, Expr)

# eval(m::MonomialRegression) = eval(m.expr)

function model(::Type{MonomialRegression}, ex::Expr)
    if ex.head == :block
        return model(MonomialRegression, ex.args[2])
    end

    objective = callsites(ex, :optimize)[end].args[2]
    f = filter(isexpr, findfunc(ex, :f))[1]
    interval = findassign(ex, :a₀)[1]
    ldef = filter(isexpr, findfunc(ex, objective))
    coeff = funcarg(ldef[1])
    return MonomialRegression(ex,
                              f,
                              coeff,
                              objective,
                              interval)
end

function show(io::IO, m::MonomialRegression)
    write(io, "MonomialRegression(\n  f=$(repr(m.f)),\n  objective=$(repr(m.objective)),\n  coefficient=$(repr(m.coefficient)),\n  interval=$(repr(m.interval)))")
end

function (t::Pow)(m::MonomialRegression)
    x = m.f.args[1].args[3]
    replacer(a::Any) = a
    replacer(ex::Expr) = begin
        if ex.head == :call && ex.args[1] == :(^)
            # increment the power
            try
                ex.args[3]+=t.inc
            catch
                @warn "Possible invalid xform"
                @show ex
            end
        end
        return ex
    end
    m.f.args[2] = postwalk(replacer, m.f.args[2])
end

#
# # Let m be a model like

# f(x,y,z) = a*x + b*y + c *z
# x,y,z = rand(Normal(0,1), (n,3))
# target[i] = f(x[i],y[i],z[i]) + rand(Normal(0,1), 1)
# a,b,c = min_{a,b,c} sum_i (f(x[i],y[i],z[i]) - target[i])^2
# So it is a 3variate least squares regression model. Define the set of transformations $T$ as the free monoid generated by

# x^i->x^i+1
# x^i->x^i-1
# y^i->y^i+1
# y^i->y^i-1
# z^i->z^i+1
# z^i->z^i-1
# The free monoid over this set of transformations is actually the product of cyclic groups Z^3 = Z x Z x Z with the group operation of +:Z^3->Z^3. so you get the set of models:

# f(x,y,z) = a*x^i + b*y^j + c *z^k
# x,y,z = rand(Normal(0,1), (n,3))
# target[i] = f(x[i],y[i],z[i]) + rand(Normal(0,1), 1)
# a,b,c = min_{a,b,c} sum_i (f(x[i],y[i],z[i]) - target[i])^2
# for all combinations of integers i,j,k which is a pretty cool structure. If you do the transformations with i mod N then you get Z_N^3 which is a finite abelian group. It doesn't get more computationally tractable than component-wise arithmetic mod N.

# We could then talk about the orbits of a given model under this group. For this group, there is only one orbit, but if you take subgroups like the group generated by (1,1,1) aka<1,1,1> you get multiple orbits. For example if you start with

# f(x,y,z) = a*x^1 + b*y^2 + c *z^3
# x,y,z = rand(Normal(0,1), (n,3))
# target[i] = f(x[i],y[i],z[i]) + rand(Normal(0,1), 1)
# a,b,c = min_{a,b,c} sum_i (f(x[i],y[i],z[i]) - target[i])^2
# the orbit is all of the models of the form

# f(x,y,z) = a*x^1+i + b*y^2+i + c *z^3+i
# x,y,z = rand(Normal(0,1), (n,3))
# target[i] = f(x[i],y[i],z[i]) + rand(Normal(0,1), 1)
# a,b,c = min_{a,b,c} sum_i (f(x[i],y[i],z[i]) - target[i])^2
# where i is in Z mod N. You could reason about finding the best fitting model from a given orbit. and then comparing the orbits to see which one was contained the best fitting model.
# ex = Base.Meta.Parse("module M ... end")
# m = ModelTools.model(ModelTypeA, ex)
# T = ConcatTransform()
# T = AXform(:addvar, :β) ∘ T
# T = AXform(:addrule, :β=>α/2) ∘ T
# m′ = T(m)
# M = eval(Expr(m′))
# sol = M.solve()
end

using SemanticModels
using .Transformations
using SemanticModels.ModelTools
if false

expr = quote
    module Regression
    using Random
    mid(a,b) = (a+b)/2
    function f(a, x)
        return a*x^4
    end

    function optimize(l, interval)
        left = interval[1]
        right = interval[2]
        if left > right - 1e-8
            return (interval)
        end
        midp = (left+right)/2
        if l(mid(left, midp)) > l(mid(midp, right))
            return optimize(l, (midp, right))
        else
            return optimize(l, (left, midp))
        end
    end

    function sample(g::Function, n::Int)
        x = randn(Float64, n)
        target = g(x) .+ randn(Float64, n)./8
        return x, target
    end


    #setup

    Random.seed!(42)
    a = 1/2
    n = 10
    g(x) = a.*x.^2
    x, target = sample(g, n)
    loss(a) = sum((f.(a, x) .- target).^2)
    a₀ = [-1, 1]
    # @show loss.([-1,-1/2,-1/4, 0, 1/4,1/3,1/2,2/3, 1])

    #solving
    ahat = optimize(loss, a₀)

    end
end

m = model(MonomialRegression, expr)
println(m)
sol = eval(m.expr)
@show sol.ahat
@show sol.loss(sol.ahat[1])
results = []
for i in 1:5
    Pow(-1)(m)
    @show m.f.args[2].args[2]
    sol = eval(m.expr)
    p = m.f.args[2].args[2].args[1].args[3].args[3]
    ahat = @show sol.ahat[1]
    lhat = @show sol.loss(sol.ahat[1])
    push!(results, (i, p, ahat, lhat))
end

fmt(i::Int) = i
fmt(f::Real) = round(f, digits=7)
println("\nResults:\n\n\ni\tp\tâ\t\tl⋆\n-----------------------------")
for r in results
    println(join(fmt.(r), "\t"))
end
best = sort(results, by=x->x[end])[1][2:end]
println("Model order $(best[1]) is the best with a=$(best[2]) and loss $(best[end])")
end


expr = quote
    module Regression
    using Random
    mid(a,b) = (a+b)/2
    function f(a, x, y)
        return a*x^4 + b*y^2
    end

    function optimize(l, interval)
        left = interval[1]
        right = interval[2]
        if left > right - 1e-8
            return (interval)
        end
        midp = (left+right)/2
        if l(mid(left, midp)) > l(mid(midp, right))
            return optimize(l, (midp, right))
        else
            return optimize(l, (left, midp))
        end
    end

    function sample(g::Function, n::Int)
        x = randn(Float64, n)
        target = g(x) .+ randn(Float64, n)./8
        return x, target
    end


    #setup

    Random.seed!(42)
    a = 1/2
    n = 10
    g(x) = a.*x.^2
    x, target = sample(g, n)
    loss(a) = sum((f.(a, x) .- target).^2)
    a₀ = [-1, 1]
    # @show loss.([-1,-1/2,-1/4, 0, 1/4,1/3,1/2,2/3, 1])

    #solving
    ahat = optimize(loss, a₀)

    end
end
