#--------------------------------------------------------
# external packages
#--------------------------------------------------------
using Crayons.Box
using DifferentialEquations
using Revise
using WriteVTK

#Constants
const TInt   = Int64
const TFloat = Float64

#--------------------------------------------------------
# jexpresso modules
#--------------------------------------------------------
include("../IO/mod_initialize.jl")
include("../IO/mod_inputs.jl")
include("../Mesh/mod_mesh.jl")
include("../solver/mod_solution.jl")
include("../basis/basis_structs.jl")
include("../Infrastructure/Kopriva_functions.jl")
include("../Infrastructure/2D_3D_structures.jl")
include("../element_matrices.jl")
include("../IO/plotting/jeplots.jl")
#--------------------------------------------------------


abstract type AbstractDiscretization end
struct CG <:  AbstractDiscretization end

abstract type AbstractProblem end
struct AD1D <: AbstractProblem end
struct NS1D <: AbstractProblem end
struct BURGERS1D <: AbstractProblem end


abstract type AbstractBC end
struct PERIODIC1D_CG <: AbstractBC end

function driver(DT::CG,        #Space discretization type
                ET::AD1D,      #Equation subtype
                inputs::Dict,  #input parameters from src/user_input.jl
                TFloat) 
    
    Nξ = inputs[:nop]
    lexact_integration = inputs[:lexact_integration]
    
    #--------------------------------------------------------
    # Create/read mesh
    # return mesh::St_mesh
    # and Build interpolation nodes
    #             the user decides among LGL, GL, etc. 
    # Return:
    # ξ = ND.ξ.ξ
    # ω = ND.ξ.ω
    #--------------------------------------------------------
    mesh = mod_mesh_mesh_driver(inputs)

    #--------------------------------------------------------
    ND = build_nodal_Storage([Nξ], LGL1D(), NodalGalerkin()) # --> ξ <- ND.ξ.ξ
    ξ  = ND.ξ.ξ
    
    if lexact_integration
        #
        # Exact quadrature:
        # Quadrature order (Q = N+1) ≠ polynomial order (N)
        #
        QT  = Exact() #Quadrature Type
        Qξ  = Nξ + 1
        
        NDQ = build_nodal_Storage([Qξ], LGL1D(), NodalGalerkin()) # --> ξ <- ND.ξ.ξ
        ξq  = NDQ.ξ.ξ
        ω   = NDQ.ξ.ω
        
    else  
        #
        # Inexact quadrature:
        # Quadrature and interpolation orders coincide (Q = N)
        #
        QT  = Inexact() #Quadrature Type
        Qξ  = Nξ
        NDQ = ND
        ξq  = ξ
        ω   = ND.ξ.ω
    end
    
    
    if (mesh.nsd == 1)
        SD = nsd1D()
    elseif (mesh.nsd == 2)
        SD = nsd2D()        
    elseif (mesh.nsd == 3)
        SD = nsd3D()
    end
       
    
 
    #--------------------------------------------------------
    # Build Lagrange polynomials:
    #
    # Return:
    # ψ     = basis.ψ[N+1, Q+1]
    # dψ/dξ = basis.dψ[N+1, Q+1]
    #--------------------------------------------------------
    basis = build_Interpolation_basis!(LagrangeBasis(), SD, TFloat, ξ, ξq)

    @info size(basis.ψ)
    
@info "2d basis built DONE"
return 
    #periodicity flag array
    periodicity = zeros(Int64, mesh.npoin)
    for iel = 1:mesh.nelem
        for i = 1:mesh.ngl
            ip = mesh.conn[i, iel]
            periodicity[ip]=ip
        end
    end
    periodicity[mesh.npoin_linear]=1
    
    #--------------------------------------------------------
    # Build element mass matrix
    #
    # Return:
    # el_mat.M[iel, i, j] <-- if exact (full)
    # el_mat.M[iel, i]    <-- if inexact (diagonal)
    # el_mat.D[iel, i, j] <-- either exact (full) OR inexact (sparse)
    #--------------------------------------------------------
    el_mat    = build_element_matrices!(QT, basis.ψ, basis.dψ, ω, mesh, Nξ, Qξ, TFloat)
    (M, Minv) = DSS(QT,      el_mat.M, periodicity, mesh.conn, mesh.nelem, mesh.npoin, Nξ, TFloat)
    (D, Dinv) = DSS(Exact(), el_mat.D, periodicity, mesh.conn, mesh.nelem, mesh.npoin, Nξ, TFloat)
    
    #initial condition --> q.qn
    q         = mod_initialize_initialize(mesh, inputs, TFloat)
    
    Δt = inputs[:Δt]
    C = 0.1
    u = 2.0
    Δt = C*u*minimum(mesh.Δx)/mesh.nop
    Nt = floor((inputs[:tend] - inputs[:tinit])/Δt)
    
    plt = scatter() #Clear plot
    #display(scatter(mesh.x, q.qn))
    

    RKA = [(0), 
           (-567301805773) / (1357537059087), 
           (-2404267990393) / (2016746695238), 
           (-3550918686646) / (2091501179385), 
           (-1275806237668) / (842570457699 )];

    RKB = [(1432997174477) / (9575080441755 ),
           (5161836677717) / (13612068292357),
           (1720146321549) / (2090206949498 ),
           (3134564353537) / (4481467310338 ),
           (2277821191437) / (14882151754819)];

    RKC = [(0),
           (1432997174477) / (9575080441755),
           (2526269341429) / (6820363962896),
           (2006345519317) / (3224310063776),
           (2802321613138) / (2924317926251)];
    
    qnp1 = copy(q.qn)
    dq   = zeros(mesh.npoin);
    R    = zeros(mesh.npoin);
    qp   = copy(q.qn)
    for it = 1:Nt
        #@show it, Δt
        
        for s = 1:length(RKA)
            
            #Create RHS Matrix
            for I = 1:mesh.npoin
                for J = 1:mesh.npoin
                    R[I] = Minv[I]*D[I,J]*qp[J] #only valid for CG
                end
            end
            
            #RHS = drivers_build_rhs(AD1D(), mesh, el_mat, qp, periodicity)
            #R = RHS.*Minv
            
            #Solve System
            for I=1:mesh.npoin
                dq[I] = RKA[s]*dq[I] + Δt*R[I]
                qp[I] = qp[I] + RKB[s]*dq[I]
            end
            for I=1:mesh.npoin
                if (periodicity[mesh.npoin_linear] == periodicity[I])
                    qp[I] = qp[1] #periodicity
                end
            end
        end #s
    end
    
      
    display(scatter())
    display(scatter!(mesh.x, qp))
    
    
end

function drivers_build_rhs(PT::AD1D, mesh::St_mesh, el_mat, q, periodicity)
    
    RHS = zeros(mesh.npoin)
    f   = zeros(mesh.ngl^mesh.nsd)
    u   = 2.0 #m/s

    for iel = 1:mesh.nelem
        for i = 1:mesh.ngl
            ip = mesh.conn[i, iel]
            f[i] = u*q[ip]
        end
        
        for i = 1:mesh.ngl
            ip = mesh.conn[i, iel]
            for j = 1:mesh.ngl
                RHS[ip] = RHS[ip] + el_mat.D[j,i,iel]*f[i]
            end
        end
    end

    #Zero-out the RHS row corresponding to the periodic node
    for ip=1:mesh.npoin
        #if (periodicity[ip] == 1)
        if( mesh.x[ip] > 0.999999)
            @show ip mesh.x[ip]
            RHS[ip] = 0
        end
    end
    
    return RHS  
end