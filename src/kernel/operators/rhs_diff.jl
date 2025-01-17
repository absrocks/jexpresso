#---------------------------------------------------------------------------
# Fetch problem name to access the user_rhs functions
#---------------------------------------------------------------------------
if (length(ARGS) === 1) #problem_
    user_flux_dir   = string("../../problems/", ARGS[1], "/user_flux.jl")
    user_source_dir = string("../../problems/", ARGS[1], "/user_source.jl")
elseif (length(ARGS) === 2)  #problem_name/problem_case_name
    user_flux_dir   = string("../../problems/", ARGS[1], "/", ARGS[2], "/user_flux.jl")
    user_source_dir = string("../../problems/", ARGS[1], "/", ARGS[2], "/user_source.jl")
end
include(user_flux_dir)
include(user_source_dir)
include("../ArtificialViscosity/DynSGS.jl")
#---------------------------------------------------------------------------

#
# AdvDiff
#
function build_rhs_diff(SD::NSD_1D, QT::Inexact, PT::AdvDiff, qp::Array, nvars, basis, ω, νx, νy, mesh::St_mesh, metrics::St_metrics, T)

    N           = mesh.ngl - 1
    qnel        = zeros(mesh.ngl, mesh.nelem)
    rhsdiffξ_el = zeros(mesh.ngl, mesh.nelem)
    
    #
    # Add diffusion ν∫∇ψ⋅∇q (ν = const for now)
    #
    for iel=1:mesh.nelem
        Jac = mesh.Δx[iel]/2.0
        dξdx = 2.0/mesh.Δx[iel]
        
        for i=1:mesh.ngl
            qnel[i,iel,1] = qp[mesh.connijk[i,iel], 1]
        end
        
        for k = 1:mesh.ngl
            ωJk = ω[k]*Jac
            
            dqdξ = 0.0
            for i = 1:mesh.ngl
                dqdξ = dqdξ + basis.dψ[i,k]*qnel[i,iel]
            end
            dqdx = dqdξ*dξdx            
            ∇ξ∇q = dξdx*dqdx
            
            for i = 1:mesh.ngl
                hll     = basis.ψ[k,k]
                dhdξ_ik = basis.dψ[i,k]
                
                rhsdiffξ_el[i, iel] -= ωJk * basis.dψ[i,k] * basis.ψ[k,k]*∇ξ∇q
            end
        end
    end
      
    return rhsdiffξ_el*νx
end

function build_rhs_diff(SD::NSD_2D, QT::Inexact, PT::AdvDiff, qp::Array, nvars, basis, ω, νx, νy, mesh::St_mesh, metrics::St_metrics, T)

    N = mesh.ngl - 1
    
    qnel = zeros(mesh.ngl,mesh.ngl,mesh.nelem)
    
    rhsdiffξ_el = zeros(mesh.ngl,mesh.ngl,mesh.nelem)
    rhsdiffη_el = zeros(mesh.ngl,mesh.ngl,mesh.nelem)
    
    #
    # Add diffusion ν∫∇ψ⋅∇q (ν = const for now)
    #
    for iel=1:mesh.nelem

        for j=1:mesh.ngl, i=1:mesh.ngl
            m = mesh.connijk[i,j,iel]            
            qnel[i,j,iel,1] = qp[m,1]
        end
        
        for k = 1:mesh.ngl, l = 1:mesh.ngl
            ωJkl = ω[k]*ω[l]*metrics.Je[k, l, iel]
            
            dqdξ = 0.0
            dqdη = 0.0
            for i = 1:mesh.ngl
                dqdξ = dqdξ + basis.dψ[i,k]*qnel[i,l,iel]
                dqdη = dqdη + basis.dψ[i,l]*qnel[k,i,iel]
            end
            
            dqdx = dqdξ*metrics.dξdx[k,l,iel] + dqdη*metrics.dηdx[k,l,iel]
            dqdy = dqdξ*metrics.dξdy[k,l,iel] + dqdη*metrics.dηdy[k,l,iel]
            
            ∇ξ∇q_kl = metrics.dξdx[k,l,iel]*dqdx + metrics.dξdy[k,l,iel]*dqdy
            ∇η∇q_kl = metrics.dηdx[k,l,iel]*dqdx + metrics.dηdy[k,l,iel]*dqdy
            
            for i = 1:mesh.ngl
                hll,     hkk     =  basis.ψ[l,l],  basis.ψ[k,k]
                dhdξ_ik, dhdη_il = basis.dψ[i,k], basis.dψ[i,l]
                
                rhsdiffξ_el[i,l,iel] -= ωJkl*dhdξ_ik*hll*∇ξ∇q_kl
                rhsdiffη_el[k,i,iel] -= ωJkl*hkk*dhdη_il*∇η∇q_kl
            end
        end
    end

    return (rhsdiffξ_el*νx + rhsdiffη_el*νy)
    
end

#
# LinearCLaw
#
function build_rhs_diff(SD::NSD_2D, QT, PT::LinearCLaw, qp, neqs, basis, ω, νx, νy, mesh::St_mesh, metrics::St_metrics, T)
    
    N = mesh.ngl - 1

    qnel = zeros(mesh.ngl,mesh.ngl,mesh.nelem, neqs)

    rhsdiffξ_el = zeros(mesh.ngl, mesh.ngl, mesh.nelem, neqs)
    rhsdiffη_el = zeros(mesh.ngl, mesh.ngl, mesh.nelem, neqs)
    qq = zeros(mesh.npoin,neqs)

    #
    # qp[1:npoin]         <-- qq[1:npoin, "p"]
    # qp[npoin+1:2npoin]  <-- qq[1:npoin, "u"]
    # qp[2npoin+1:3npoin] <-- qq[1:npoin, "v"]
    #
    for i=1:neqs
        idx = (i-1)*mesh.npoin
        qq[:,i] = qp[idx+1:i*mesh.npoin]
    end
    #
    # Add diffusion ν∫∇ψ⋅∇q (ν = const for now)
    #
    for iel=1:mesh.nelem

        for j=1:mesh.ngl, i=1:mesh.ngl
            m = mesh.connijk[i,j,iel]
            qnel[i,j,iel,1:neqs] = qq[m,1:neqs]
        end

        for k = 1:mesh.ngl, l = 1:mesh.ngl
            ωJkl = ω[k]*ω[l]*metrics.Je[k, l, iel]

            for ieq = 1:neqs
                dqdξ = 0.0
                dqdη = 0.0
                for i = 1:mesh.ngl
                    dqdξ = dqdξ + basis.dψ[i,k]*qnel[i,l,iel,ieq]
                    dqdη = dqdη + basis.dψ[i,l]*qnel[k,i,iel,ieq]
                end
                dqdx = dqdξ*metrics.dξdx[k,l,iel] + dqdη*metrics.dηdx[k,l,iel]
                dqdy = dqdξ*metrics.dξdy[k,l,iel] + dqdη*metrics.dηdy[k,l,iel]

                ∇ξ∇q_kl = metrics.dξdx[k,l,iel]*dqdx + metrics.dξdy[k,l,iel]*dqdy
                ∇η∇q_kl = metrics.dηdx[k,l,iel]*dqdx + metrics.dηdy[k,l,iel]*dqdy

                for i = 1:mesh.ngl

                    hll,     hkk     = basis.ψ[l,l],  basis.ψ[k,k]
                    dhdξ_ik, dhdη_il = basis.dψ[i,k], basis.dψ[i,l]

                    rhsdiffξ_el[i,l,iel, ieq] -= ωJkl*dhdξ_ik*hll*∇ξ∇q_kl
                    rhsdiffη_el[k,i,iel, ieq] -= ωJkl*hkk*dhdη_il*∇η∇q_kl
                end
            end
        end
     end

    return (rhsdiffξ_el*νx + rhsdiffη_el*νy)

end


#
# ShallowWater
#
function build_rhs_diff(SD::NSD_1D, QT, PT::ShallowWater, qp, neqs, basis, ω, νx, νy, mesh::St_mesh, metrics::St_metrics, mu, T)

    N = mesh.ngl - 1

    qnel = zeros(mesh.ngl, mesh.nelem, neqs)

    rhsdiffξ_el = zeros(mesh.ngl, mesh.nelem, neqs)
    qq = zeros(mesh.npoin,neqs)

    #
    # qp[1:npoin]         <-- qq[1:npoin, "p"]
    # qp[npoin+1:2npoin]  <-- qq[1:npoin, "u"]
    # qp[2npoin+1:3npoin] <-- qq[1:npoin, "v"]
    #
    for i=1:neqs
        idx = (i-1)*mesh.npoin
        qq[:,i] = qp[idx+1:i*mesh.npoin]
    end
    #
    # Add diffusion ν∫∇ψ⋅∇q (ν = const for now)
    #
    for iel=1:mesh.nelem
        Jac = mesh.Δx[iel]/2.0
        for i=1:mesh.ngl
            m = mesh.conn[i,iel]
            qnel[i,iel,1] = qq[m,1]
            qnel[i,iel,2] = qq[m,2]/qq[m,1]
        end
        dξdx = 2.0/mesh.Δx[iel]
        for k = 1:mesh.ngl
            ωJkl = ω[k]*Jac

            for ieq = 1:neqs
                dqdξ = 0.0
                for i = 1:mesh.ngl
                    dqdξ = dqdξ + basis.dψ[i,k]*qnel[i,iel,ieq]
                    #@info "contribution", basis.dψ[i,k]*qnel[k,iel,ieq]
                end
                #@info "dqdxi", dqdξ
                #if (ieq > 1)
                    dqdx = mu[iel] * (dqdξ) * dξdx
                #else
                #    dqdx = 0.0
                #end 
                #@info "dqdx", dqdx, "vx", νx
                
                if (ieq > 1)
                    ip = mesh.conn[k,iel]
                    x = mesh.x[ip]
                    Hb = bathymetry(x)
                    Hs = max(qq[ip,1] - Hb,0.001)
                    dqdx = dqdx * qq[ip,1]#* Hs
                end

                ∇ξ∇q_kl =  dqdx*dξdx 
                for i = 1:mesh.ngl

                    hkk     = basis.ψ[k,k]
                    dhdξ_ik = basis.dψ[i,k]

                    rhsdiffξ_el[i,iel,ieq] -= ωJkl*dhdξ_ik*hkk*∇ξ∇q_kl
                end
            end
        end
     end
    
    return (rhsdiffξ_el)

end

function build_rhs_diff(SD::NSD_2D, QT, PT::ShallowWater, qp, neqs, basis, ω, νx, νy, mesh::St_mesh, metrics::St_metrics, T)
    
    N = mesh.ngl - 1

    qnel = zeros(mesh.ngl,mesh.ngl,mesh.nelem, neqs)

    rhsdiffξ_el = zeros(mesh.ngl, mesh.ngl, mesh.nelem, neqs)
    rhsdiffη_el = zeros(mesh.ngl, mesh.ngl, mesh.nelem, neqs)
    qq = zeros(mesh.npoin,neqs)

    #
    # qp[1:npoin]         <-- qq[1:npoin, "p"]
    # qp[npoin+1:2npoin]  <-- qq[1:npoin, "u"]
    # qp[2npoin+1:3npoin] <-- qq[1:npoin, "v"]
    #
    for i=1:neqs
        idx = (i-1)*mesh.npoin
        qq[:,i] = qp[idx+1:i*mesh.npoin]
    end
    #
    # Add diffusion ν∫∇ψ⋅∇q (ν = const for now)
    #
    for iel=1:mesh.nelem

        for j=1:mesh.ngl, i=1:mesh.ngl
            m = mesh.connijk[i,j,iel]
            qnel[i,j,iel,1] = qq[m,1]
            qnel[i,j,iel,2] = qq[m,2]/qq[m,1]
            qnel[i,j,iel,3] = qq[m,3]/qq[m,1]
        end

        for k = 1:mesh.ngl, l = 1:mesh.ngl
            ωJkl = ω[k]*ω[l]*metrics.Je[k, l, iel]

            for ieq = 1:neqs
                dqdξ = 0.0
                dqdη = 0.0
                for i = 1:mesh.ngl
                    dqdξ = dqdξ + basis.dψ[i,k]*qnel[i,l,iel,ieq]
                    dqdη = dqdη + basis.dψ[i,l]*qnel[k,i,iel,ieq]
                end
                dqdx = νx * (dqdξ*metrics.dξdx[k,l,iel] + dqdη*metrics.dηdx[k,l,iel])
                dqdy = νy * (dqdξ*metrics.dξdy[k,l,iel] + dqdη*metrics.dηdy[k,l,iel])
                if (ieq > 1)
                    ip = mesh.connijk[k,l,iel]
                    x = mesh.x[ip]
                    y = mesh.y[ip]
                    Hb = bathymetry(x,y)
                    Hs = qq[ip,1] - Hb
                    dqdx = dqdx * Hs
                    dqdy = dqdy * Hs
                end                

                ∇ξ∇q_kl =  (metrics.dξdx[k,l,iel]*dqdx + metrics.dξdy[k,l,iel]*dqdy)
                ∇η∇q_kl =  (metrics.dηdx[k,l,iel]*dqdx + metrics.dηdy[k,l,iel]*dqdy)

                for i = 1:mesh.ngl

                    hll,     hkk     = basis.ψ[l,l],  basis.ψ[k,k]
                    dhdξ_ik, dhdη_il = basis.dψ[i,k], basis.dψ[i,l]
     
                    rhsdiffξ_el[i,l,iel, ieq] -= ωJkl*dhdξ_ik*hll*∇ξ∇q_kl
                    rhsdiffη_el[k,i,iel, ieq] -= ωJkl*hkk*dhdη_il*∇η∇q_kl
                end
            end
        end
     end

    return (rhsdiffξ_el + rhsdiffη_el)

end

#
# CompEuler
#
function build_rhs_diff(SD::NSD_1D, QT, PT::CompEuler, qp, neqs, basis, ω, νx, νy, mesh::St_mesh, metrics::St_metrics, μ, T)

    N = mesh.ngl - 1

    #qnel = zeros(mesh.ngl, mesh.nelem, neqs)
    ρel = zeros(mesh.ngl, mesh.nelem)
    uel = zeros(mesh.ngl, mesh.nelem)
    Tel = zeros(mesh.ngl, mesh.nelem)
    Eel = zeros(mesh.ngl, mesh.nelem)

    rhsdiffξ_el = zeros(mesh.ngl, mesh.nelem, neqs)
    qq = zeros(mesh.npoin,neqs)

    γ = 1.4
    Pr = 0.1
    
    #
    # qp[1:npoin]         <-- qq[1:npoin, "ρ"]
    # qp[npoin+1:2npoin]  <-- qq[1:npoin, "ρu"]
    # qp[2npoin+1:3npoin] <-- qq[1:npoin, "ρE"]
    #
    for i=1:neqs
        idx = (i-1)*mesh.npoin
        qq[:,i] = qp[idx+1:i*mesh.npoin]
    end
    #
    # Add diffusion ν∫∇ψ⋅∇q (ν = const for now)
    #
    for iel=1:mesh.nelem
        Jac = mesh.Δx[iel]/2.0
        for i=1:mesh.ngl
            m = mesh.conn[i,iel]
            #qnel[i,iel,1] = qq[m,1] #ρ
            #qnel[i,iel,2] = qq[m,2]/qnel[i,iel,1] #u = ρu/ρ
            #qnel[i,iel,3] = qq[m,3]/qnel[i,iel,1] #E = ρE/ρ
            
            ρel[i,iel] = qq[m,1]
            uel[i,iel] = qq[m,2]/ρel[i]
            Tel[i,iel] = qq[m,3]/ρel[i] - 0.5*uel[i]^2
            Eel[i,iel] = qq[m,3]/ρel[i]
        end
        
        ν = Pr*μ[iel]/maximum(ρel[:,iel])
        κ = Pr*μ[iel]/(γ - 1.0)
        
        dξdx = 2.0/mesh.Δx[iel]
        for k = 1:mesh.ngl
            ωJkl = ω[k]*Jac

            #for ieq = 1:neqs
            #dqdξ = 0.0
            dρdξ = 0.0
            dudξ = 0.0
            dTdξ = 0.0
            dEdξ = 0.0
            for i = 1:mesh.ngl
                #dqdξ = dqdξ + basis.dψ[i,k]*qnel[i,iel,ieq]
                dρdξ = dρdξ + basis.dψ[i,k]*ρel[i,iel]
                dudξ = dudξ + basis.dψ[i,k]*uel[i,iel]
                dTdξ = dTdξ + basis.dψ[i,k]*Tel[i,iel]
                dEdξ = dEdξ + basis.dψ[i,k]*Eel[i,iel]
            end
            
            dρdx =  ν * dρdξ*dξdx
            dudx =  μ[iel] * dudξ*dξdx
            dTdx = (μ[iel] * dudξ*dξdx * uel[k,iel] + κ * dTdξ*dξdx)
            
            #∇ξ∇q_kl =  dqdx*dξdx
            ∇ξ∇ρ_kl =  dρdx*dξdx
            ∇ξ∇u_kl =  dudx*dξdx
            ∇ξ∇T_kl =  dTdx*dξdx
            for i = 1:mesh.ngl

                hkk     = basis.ψ[k,k]
                dhdξ_ik = basis.dψ[i,k]

                rhsdiffξ_el[i,iel,1] -= ωJkl*dhdξ_ik*hkk*∇ξ∇ρ_kl
                rhsdiffξ_el[i,iel,2] -= ωJkl*dhdξ_ik*hkk*∇ξ∇u_kl
                rhsdiffξ_el[i,iel,3] -= ωJkl*dhdξ_ik*hkk*∇ξ∇T_kl
            end
            # end
        end
    end
    
    return (rhsdiffξ_el)

end

function build_rhs_diff(SD::NSD_2D, QT, PT::CompEuler, qp, neqs, basis, ω, νx, νy, mesh::St_mesh, metrics::St_metrics, μ, T)

    N = mesh.ngl - 1

    #qnel = zeros(mesh.ngl, mesh.nelem, neqs)
    ρel = zeros(mesh.ngl, mesh.ngl, mesh.nelem)
    uel = zeros(mesh.ngl, mesh.ngl, mesh.nelem)
    vel = zeros(mesh.ngl, mesh.ngl, mesh.nelem)
    Tel = zeros(mesh.ngl, mesh.ngl, mesh.nelem)
    Eel = zeros(mesh.ngl, mesh.ngl, mesh.nelem)

    rhsdiffξ_el = zeros(mesh.ngl, mesh.ngl, mesh.nelem, neqs)
    rhsdiffη_el = zeros(mesh.ngl, mesh.ngl, mesh.nelem, neqs)
    return  (rhsdiffξ_el + rhsdiffη_el)
    qq = zeros(mesh.npoin, neqs)

    γ = 1.4
    Pr = 0.1
    
    #
    # qp[1:npoin]         <-- qq[1:npoin, "ρ"]
    # qp[npoin+1:2npoin]  <-- qq[1:npoin, "ρu"]
    # qp[2npoin+1:3npoin] <-- qq[1:npoin, "ρE"]
    #
    for i=1:neqs
        idx = (i-1)*mesh.npoin
        qq[:,i] = qp[idx+1:i*mesh.npoin]
    end
    #
    # Add diffusion ν∫∇ψ⋅∇q (ν = const for now)
    #
    for iel=1:mesh.nelem

        μ[iel] = 10.0
        
        for j=1:mesh.ngl, i=1:mesh.ngl
            m = mesh.connijk[i,j,iel]
            
            ρel[i,j,iel] = qq[m,1]
            uel[i,j,iel] = qq[m,2]/ρel[i,j,iel]
            vel[i,j,iel] = qq[m,3]/ρel[i,j,iel]
            Tel[i,j,iel] = qq[m,4]/ρel[i,j,iel] - 0.5*(uel[i,j,iel]^2 + vel[i,j,iel]^2)
            Eel[i,j,iel] = qq[m,4]/ρel[i,j,iel]
        end    
        #ν = Pr*μ[iel]/maximum(ρel[:,:,iel])
        #κ = Pr*μ[iel]/(γ - 1.0)
        ν = 10.0
        κ = 10.0
        
        for k = 1:mesh.ngl, l = 1:mesh.ngl
            ωJkl = ω[k]*ω[l]*metrics.Je[k, l, iel]
            
            #for ieq = 1:neqs
            #dqdξ = 0.0
            dρdξ = 0.0
            dudξ = 0.0
            dvdξ = 0.0
            dTdξ = 0.0
            dEdξ = 0.0

            dρdη = 0.0
            dudη = 0.0
            dvdη = 0.0
            dTdη = 0.0
            dEdη = 0.0
            for i = 1:mesh.ngl
                dρdξ = dρdξ + basis.dψ[i,k]*ρel[i,l,iel]
                dudξ = dudξ + basis.dψ[i,k]*uel[i,l,iel]
                dvdξ = dvdξ + basis.dψ[i,k]*vel[i,l,iel]
                dTdξ = dTdξ + basis.dψ[i,k]*Tel[i,l,iel]
                dEdξ = dEdξ + basis.dψ[i,k]*Eel[i,l,iel]

                dρdη = dρdη + basis.dψ[i,l]*ρel[k,i,iel]
                dudη = dudη + basis.dψ[i,l]*uel[k,i,iel]
                dvdη = dvdη + basis.dψ[i,l]*vel[k,i,iel]
                dTdη = dTdη + basis.dψ[i,l]*Tel[k,i,iel]
                dEdη = dEdη + basis.dψ[i,l]*Eel[k,i,iel]
            end
            
            dρdx =       ν*(dρdξ*metrics.dξdx[k,l,iel] + dρdη*metrics.dηdx[k,l,iel])
            dudx =  μ[iel]*(dudξ*metrics.dξdx[k,l,iel] + dudη*metrics.dηdx[k,l,iel])
            dvdx =  μ[iel]*(dvdξ*metrics.dξdx[k,l,iel] + dvdη*metrics.dηdy[k,l,iel])
            dTdx =       κ*(dTdξ*metrics.dξdx[k,l,iel] + dTdη*metrics.dηdx[k,l,iel]) #+μ∇u⋅u
          
            dρdy =       ν*(dρdξ*metrics.dξdy[k,l,iel] + dρdη*metrics.dηdy[k,l,iel])
            dudy =  μ[iel]*(dudξ*metrics.dξdy[k,l,iel] + dudη*metrics.dηdy[k,l,iel])
            dvdy =  μ[iel]*(dvdξ*metrics.dξdy[k,l,iel] + dvdη*metrics.dηdy[k,l,iel])
            dTdy =       κ*(dTdξ*metrics.dξdy[k,l,iel] + dTdη*metrics.dηdy[k,l,iel]) #+μ∇u⋅u
            
            ∇ξ∇ρ_kl = metrics.dξdx[k,l,iel]*dρdx + metrics.dξdy[k,l,iel]*dρdy
            ∇η∇ρ_kl = metrics.dηdx[k,l,iel]*dρdx + metrics.dηdy[k,l,iel]*dρdy
            
            ∇ξ∇u_kl = metrics.dξdx[k,l,iel]*dudx + metrics.dξdy[k,l,iel]*dudy
            ∇η∇u_kl = metrics.dηdx[k,l,iel]*dudx + metrics.dηdy[k,l,iel]*dudy            
            ∇ξ∇v_kl = metrics.dξdx[k,l,iel]*dvdx + metrics.dξdy[k,l,iel]*dvdy
            ∇η∇v_kl = metrics.dηdx[k,l,iel]*dvdx + metrics.dηdy[k,l,iel]*dvdy

            ∇ξ∇T_kl = metrics.dξdx[k,l,iel]*dTdx + metrics.dξdy[k,l,iel]*dTdy
            ∇η∇T_kl = metrics.dηdx[k,l,iel]*dTdx + metrics.dηdy[k,l,iel]*dTdy
            
            for i = 1:mesh.ngl
                
                hll,     hkk     =  basis.ψ[l,l],  basis.ψ[k,k]
                dhdξ_ik, dhdη_il = basis.dψ[i,k], basis.dψ[i,l]
                
                rhsdiffξ_el[i,l,iel,1] -= ωJkl*dhdξ_ik*hll*∇ξ∇ρ_kl
                rhsdiffη_el[k,i,iel,1] -= ωJkl*hkk*dhdη_il*∇η∇ρ_kl
                
                rhsdiffξ_el[i,l,iel,2] -= ωJkl*dhdξ_ik*hll*∇ξ∇u_kl
                rhsdiffη_el[k,i,iel,2] -= ωJkl*hkk*dhdη_il*∇η∇u_kl
                
                rhsdiffξ_el[i,l,iel,3] -= ωJkl*dhdξ_ik*hll*∇ξ∇v_kl
                rhsdiffη_el[k,i,iel,3] -= ωJkl*hkk*dhdη_il*∇η∇v_kl
                
                rhsdiffξ_el[i,l,iel,4] -= ωJkl*dhdξ_ik*hll*∇ξ∇T_kl
                rhsdiffη_el[k,i,iel,4] -= ωJkl*hkk*dhdη_il*∇η∇T_kl
                
            end
            # end
        end
    end
    
    return (rhsdiffξ_el + rhsdiffη_el)

end
