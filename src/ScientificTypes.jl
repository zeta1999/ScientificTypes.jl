module ScientificTypes

export Scientific, Found, Unknown, Finite, Infinite
export OrderedFactor, Multiclass, Count, Continuous
export Binary, Table
export ColorImage, GrayImage
export scitype, scitype_union, scitypes, coerce, schema
export mlj

using Tables, CategoricalArrays, ColorTypes
# using Requires
# using InteractiveUtils

# ## FOR DEFINING SCITYPES ON OBJECTS DETECTED USING TRAITS

# We define a "dynamically" extended function `trait`:

const TRAIT_FUNCTION_GIVEN_NAME = Dict()
function trait(X)
    for (name, f) in TRAIT_FUNCTION_GIVEN_NAME
        f(X) && return name
    end
    return :other
end

# Explanation: For example, if Tables.jl is loaded and one does
# `TRAIT_FUNCTION_GIVEN_NAME[:table] = Tables.is_table` then
# `trait(X)` returns `:table` on any Tables.jl table, and `:other`
# otherwise. There is an understanding here that no two trait
# functions added to the dictionary values can be simultaneously true
# on two julia objects.


# ## CONVENTIONS

const CONVENTION=[:unspecified]
convention() = CONVENTION[1]

function mlj()
    CONVENTION[1] = :mlj
    return nothing
end


# ## THE SCIENTIFIC TYPES

abstract type Found          end
abstract type Known <: Found end
struct      Unknown <: Found end

abstract type Infinite <: Known    end
struct      Continuous <: Infinite end
struct           Count <: Infinite end

abstract type Finite{N} <: Known     end
struct    Multiclass{N} <: Finite{N} end
struct OrderedFactor{N} <: Finite{N} end

abstract type Image{W,H} <: Known      end
struct    GrayImage{W,H} <: Image{W,H} end
struct   ColorImage{W,H} <: Image{W,H} end

# aliases:
const Binary     = Finite{2}
const Scientific = Union{Missing,Found}

"""
    MLJBase.Table{K}

The scientific type for tabular data (a containter `X` for which
`Tables.is_table(X)=true`).

If `X` has columns `c1, c2, ..., cn`, then, by definition,

    scitype(X) = Table{Union{scitype(c1), scitype(c2), ..., scitype(cn)}}

A special constructor of `Table` types exists:

    `Table(T1, T2, T3, ..., Tn) <: Table`

has the property that

    scitype(X) <: Table(T1, T2, T3, ..., Tn)

if and only if `X` is a table *and*, for every column `col` of `X`,
`scitype(col) <: AbstractVector{<:Tj}`, for some `j` between `1` and
`n`. Note that this constructor constructs a *type* not an instance,
as instances of scientific types play no role (except for missing).

    julia> X = (x1 = [10.0, 20.0, missing],
                x2 = [1.0, 2.0, 3.0],
                x3 = [4, 5, 6])

    julia> scitype(X) <: MLJBase.Table(Continuous, Count)
    false

    julia> scitype(X) <: MLJBase.Table(Union{Continuous, Missing}, Count)
    true

"""
struct Table{K} <: Known end
function Table(Ts...)
    Union{Ts...} <: Scientific ||
        error("Arguments of Table scitype constructor "*
              "must be scientific types. ")
    return Table{<:Union{[AbstractVector{<:T} for T in Ts]...}}
end


# ## THE SCITYPE FUNCTION

"""
    scitype(x)

The scientific type that `x` may represent.

"""
scitype(X) = scitype(X, Val(convention()))
scitype(X, C) = scitype(X, C, Val(trait(X)))
scitype(X, C, ::Val{:other}) = Unknown

scitype(::Missing) = Missing

# ## CONVENIENCE METHOD FOR UNIONS OVER ELEMENTS

"""
    scitype_union(A)

Return the type union, over all elements `x` generated by the iterable
`A`, of `scitype(x)`.

See also `scitype`.

"""
scitype_union(A) = reduce((a,b)->Union{a,b}, (scitype(el) for el in A))


# ## SCITYPES OF TUPLES

scitype(t::Tuple, ::Val) = Tuple{scitype.(t)...}


# ## SCITYPES OF ARRAYS

"""
    ScientificTypes.Scitype(::Type, C::Val)

Method for implementers of a conventions to enable speed-up of scitype
evaluations for large arrays.

In general, one cannot infer the scitype of an object of type
`AbstractArray{T, N}` from the machine type alone. For, example, this
never holds in the *mlj* convention for a categorical array, or in the
following examples: `X=Any[1, 2, 3]` and `X=Union{Missing,Int64}[1, 2,
3]`.

Nevertheless, for some *restricted* machine types `U`, the statement
`type(X) == AbstractArray{T, N}` for some `T<:U` already allows one
deduce that `scitype(X) = AbstractArray{S,N}`, where `S` is determined
by `U` alone. This is the case in the *mlj* convention, for example,
if `U = Integer`, in which case `S = Count`. If one explicitly declares

    ScientificTypes.Scitype(::Type{<:U}, ::Val{:convention}) = S

in such cases, then ScientificTypes ensures a considerable speed-up in
the computation of `scitype(X)`. There is also a partial speed-up for
the case that `T <: Union{U, Missing}`.

For example, in *mlj* one has `Scitype(::Type{<:Integer}) = Count`.

"""
Scitype(::Type, C::Val) = nothing
Scitype(::Type{Any}, C::Val) = nothing # b/s `Any` isa `Union{<:Any, Missing}`

# For all such `T` we can also get almost the same speed-up in the case that
# `T` is replaced by `Union{T, Missing}`, which we detect by wrapping
# the answer:

Scitype(MT::Type{Union{T, Missing}}, C::Val) where T = Val(Scitype(T, C))

# For example, in *mlj* convention, Scitype(::Integer) = Count

const Arr{T,N} = AbstractArray{T,N}

# the dispatcher:
scitype(A::Arr{T}, C) where T = scitype(A, C, Scitype(T, C))

# the slow fallback:
scitype(A::Arr{<:Any,N}, ::Val, ::Nothing) where N =
    AbstractArray{scitype_union(A),N}

# the speed-up:
scitype(::Arr{<:Any,N}, ::Val, S) where N = Arr{S,N}

# partial speed-up for missing types, because broadcast is faster than
# computing scitype_union:
function scitype(A::Arr{<:Any,N}, C::Val, ::Val{S}) where {N,S}
    if S == nothing
        return scitype(A, C, S)
    else
        Atight = broadcast(identity, A)
        if typeof(A) == typeof(Atight)
            return Arr{Union{S,Missing},N}
        else
            return Arr{S,N}
        end
    end
end

# ## STUB FOR COERCE METHOD

function coerce end


# ## TABLE SCHEMA

struct Schema{names, types, scitypes, nrows} end

Schema(names::Tuple{Vararg{Symbol}}, types::Type{T}, scitypes::Type{S}, nrows::Integer) where {T<:Tuple,S<:Tuple} = Schema{names, T, S, nrows}()
Schema(names, types, scitypes, nrows) = Schema{Tuple(Base.map(Symbol, names)), Tuple{types...}, Tuple{scitypes...}, nrows}()

function Base.getproperty(sch::Schema{names, types, scitypes, nrows}, field::Symbol) where {names, types, scitypes, nrows}
    if field === :names
        return names
    elseif field === :types
        return types === nothing ? nothing : Tuple(fieldtype(types, i) for i = 1:fieldcount(types))
    elseif field === :scitypes
        return scitypes === nothing ? nothing : Tuple(fieldtype(scitypes, i) for i = 1:fieldcount(scitypes))
    elseif field === :nrows
        return nrows === nothing ? nothing : nrows
    else
        throw(ArgumentError("unsupported property for ScientificTypes.Schema"))
    end
end

Base.propertynames(sch::Schema) = (:names, :types, :scitypes, :nrows)

_as_named_tuple(s::Schema) = NamedTuple{(:names, :types, :scitypes, :nrows)}((s.names, s.types, s.scitypes, s.nrows))

function Base.show(io::IO, ::MIME"text/plain", s::Schema)
    show(io, MIME("text/plain"), _as_named_tuple(s))
end


"""
    schema(X)

Inspect the column types and scitypes of a table.

    julia> X = (ncalls=[1, 2, 4], mean_delay=[2.0, 5.7, 6.0])
    julia> schema(X)
    (names = (:ncalls, :mean_delay),
     types = (Int64, Float64),
     scitypes = (Count, Continuous))

"""
schema(X) = schema(X, Val(trait(X)))
schema(X, ::Val{:other}) =
    throw(ArgumentError("Cannot inspect the internal scitypes of "*
                        "an object with trait `:other`\n"*
                        "Perhaps you meant to import Tables first?"))

include("tables.jl")
include("autotype.jl")

## ACTIVATE DEFAULT CONVENTION

# and include code not requiring optional dependencies:

mlj()
include("conventions/mlj/mlj.jl")
include("conventions/mlj/finite.jl")
include("conventions/mlj/images.jl")

end # module
