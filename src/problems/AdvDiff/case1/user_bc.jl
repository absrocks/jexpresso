"""
    qibdy is an Array{Floats} of size `nvars`

    src/problem/PROBLEM_NAME/user_bc.jl contains a set of user-defined boundary conditions functions
    that can be modified as needed.

    The function defined in src/problem/PROBLEM_NAME/user_bc.jl 
    are called by the b.c. functions defined in src/kernel/custom_bcs.jl
    within a boundary-edge loop that detects the "tag" string defined in the user-generated *.msh file.

    For example:
    If some domain boundaries of gmsh file mymesh.msh are tagged as "inflow" and "no_slip", then the user
    creating the functions in user_bc.jl must define the behavior of the unknown or its derivatives
    on those boundaries.

    ```math
    if (tag === "inflow")
        qibdy[1] = 3.0
    elseif (tag === "fix_temperature")
        qibdy[2] = 300.0
    end
    return qibdy
    ```
    where  `qibdy[i=1:nvar]` is the value unknown `i`
    
"""
function user_bc_dirichlet!(q::AbstractArray, gradq::AbstractArray, x::AbstractFloat, y::AbstractFloat, t::AbstractFloat, tag::String)

    q[1] = 0.0    
    
    return q
end

function user_bc_neumann(q::AbstractArray, gradq::AbstractArray, x::AbstractFloat, y::AbstractFloat, t::AbstractFloat, tag::String)
    flux = zeros(size(q,2),1)
    return flux
end