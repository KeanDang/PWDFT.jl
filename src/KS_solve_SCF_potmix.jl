"""
Solves Kohn-Sham problem using traditional self-consistent field (SCF)
iterations with potential mixing.

TODO: Not all mixing methods are implemented.
"""
function KS_solve_SCF_potmix!(
    Ham::Hamiltonian;
    NiterMax=150,
    betamix=0.2,
    startingwfc=:random,
    startingrhoe=:gaussian,
    verbose=true,
    print_final_ebands=false,
    print_final_energies=true,
    savewfc=false,
    use_smearing=false,
    mix_method="simple",
    mixdim=5,
    kT=1e-3,
    update_psi="LOBPCG",
    cheby_degree=8,
    etot_conv_thr=1e-6,
    ethr_evals_last=1e-5,
    starting_magnetization=nothing 
)

    Npoints = prod(Ham.pw.Ns)
    Nspin = Ham.electrons.Nspin
    Nkpt = Ham.pw.gvecw.kpoints.Nkpt
    Nkspin = Nspin*Nkpt
    Nstates = Ham.electrons.Nstates
    atoms = Ham.atoms
    pspots = Ham.pspots
    electrons = Ham.electrons
    Focc = copy(electrons.Focc) # make sure to use the copy
    Nelectrons = Ham.electrons.Nelectrons
    wk = Ham.pw.gvecw.kpoints.wk
    Nstates_occ = electrons.Nstates_occ
    dVol = Ham.pw.CellVolume/prod(Ham.pw.Ns)

    if verbose
        @printf("\n")
        @printf("Self-consistent iteration begins ...\n")
        @printf("update_psi = %s\n", update_psi)
        @printf("mix_method = %s\n", mix_method)
        if mix_method in ("rpulay", "anderson", "ppulay", "broyden")
            @printf("mixdim = %d\n", mixdim)
        end
        @printf("Potential mixing with betamix = %10.5f\n", betamix)
        if use_smearing
            @printf("Smearing = %f\n", kT)
        end
        println("") # blank line before SCF iteration info
    end

    #
    # Initial wave function
    #
    if startingwfc == :read
        psiks = read_psiks( Ham )
    else
        # generate random BlochWavefunc
        psiks = rand_BlochWavefunc( Ham )
    end

    if Ham.sym_info.Nsyms > 1
        rhoe_symmetrizer = RhoeSymmetrizer( Ham )
    end

    Rhoe = zeros(Float64,Npoints,Nspin)
    if startingrhoe == :gaussian && startingwfc == :random
        if Nspin == 1
            Rhoe[:,1] = guess_rhoe( Ham )
        else
            Rhoe = guess_rhoe_atomic( Ham, starting_magnetization=starting_magnetization )
        end
    else
        Rhoe = calc_rhoe( Ham, psiks )
    end

    # Symmetrize Rhoe is needed
    if Ham.sym_info.Nsyms > 1
        symmetrize_rhoe!( Ham, rhoe_symmetrizer, Rhoe )
    end

    if Nspin == 2 && verbose
        @printf("Initial integ Rhoe up  = %18.10f\n", sum(Rhoe[:,1])*dVol)
        @printf("Initial integ Rhoe dn  = %18.10f\n", sum(Rhoe[:,2])*dVol)
        @printf("Initial integ magn_den = %18.10f\n", sum(Rhoe[:,1] - Rhoe[:,2])*dVol)
        println("")
    end

    Vxc_inp = zeros(Float64, Npoints, Nspin)
    VHa_inp = zeros(Float64, Npoints)

    if mix_method == "broyden"
        df_VHa = zeros(Float64, Npoints, mixdim)
        df_Vxc = zeros(Float64, Npoints*Nspin, mixdim)
        #
        dv_VHa = zeros(Float64, Npoints, mixdim)
        dv_Vxc = zeros(Float64, Npoints*Nspin, mixdim)

    elseif mix_method == "linear_adaptive"
        betav_Vxc = betamix*ones(Float64, Npoints*Nspin)
        df_Vxc = zeros(Float64, Npoints*Nspin)
        #
        betav_VHa = betamix*ones(Float64, Npoints)
        df_VHa = zeros(Float64, Npoints)
    end

    update!(Ham, Rhoe)

    Ham.energies.NN = calc_E_NN(atoms)
    Ham.energies.PspCore = calc_PspCore_ene(atoms, pspots)

    evals = zeros(Nstates,Nkspin)

    Etot_old = 0.0

    Nconverges = 0

    ethr = 0.1
    diffRhoe = ones(Nspin)
    diffPot = ones(Nspin)
    Rhoe_old = zeros(Float64,Npoints,Nspin)
    E_fermi = 0.0

    if verbose
        if Nspin == 1
            @printf("--------------------------------------------------------------\n")
            @printf("              iter            E            ΔE           Δρ\n")
            @printf("--------------------------------------------------------------\n")
        else
            @printf("----------------------------------------------------------------------------\n")
            @printf("              iter            E            ΔE                  Δρ\n")
            @printf("----------------------------------------------------------------------------\n")
        end
    end

    for iterSCF = 1:NiterMax

        # determine convergence criteria for diagonalization
        if iterSCF == 1
            ethr = 0.1
        elseif iterSCF == 2
            ethr = 0.01
        else
            ethr = ethr/5.0
            ethr = max( ethr, ethr_evals_last )
        end


        if update_psi == "LOBPCG"

            evals =
            diag_LOBPCG!( Ham, psiks, verbose=false, verbose_last=false, tol=ethr,
                          Nstates_conv=Nstates_occ )

        elseif update_psi == "davidson"

            evals =
            diag_davidson!( Ham, psiks, verbose=false, verbose_last=false, tol=ethr,
                            Nstates_conv=Nstates_occ )                

        elseif update_psi == "PCG"

            evals =
            diag_Emin_PCG!( Ham, psiks, verbose=false, verbose_last=false, tol=ethr,
                            Nstates_conv=Nstates_occ )

        elseif update_psi == "CheFSI"

            evals =
            diag_CheFSI!( Ham, psiks, cheby_degree )

        else
            error( @sprintf("Unknown method for update_psi = %s\n", update_psi) )
        end


        if use_smearing
            Focc, E_fermi = calc_Focc( Nelectrons, wk, kT, evals, Nspin )
            Entropy = calc_entropy( wk, kT, evals, E_fermi, Nspin )
            Ham.electrons.Focc = copy(Focc)
        end

        Rhoe[:,:] = calc_rhoe( Ham, psiks )
        # Symmetrize Rhoe is needed
        if Ham.sym_info.Nsyms > 1
            symmetrize_rhoe!( Ham, rhoe_symmetrizer, Rhoe )
        end

        # Save the old (input) potential
        Vxc_inp[:,:] = Ham.potentials.XC
        VHa_inp[:] = Ham.potentials.Hartree

        # Update potentials
        update!(Ham, Rhoe)

        # Now Ham.potentials contains new (output) potential
        
        # Calculate energies
        Ham.energies = calc_energies(Ham, psiks)
        if use_smearing
            Ham.energies.mTS = Entropy
        end
        Etot = sum(Ham.energies)

        for ispin = 1:Nspin
            diffRhoe[ispin] = sum(abs.(@views Rhoe[:,ispin] - Rhoe_old[:,ispin]))/Npoints
        end

        diffEtot = abs(Etot - Etot_old)

        if verbose
            if Nspin == 1
                @printf("SCF_potmix: %5d %18.10f %12.5e %12.5e\n", iterSCF, Etot, diffEtot, diffRhoe[1])
            else
                @printf("SCF_potmix: %5d %18.10f %12.5e [%12.5e,%12.5e]\n",
                    iterSCF, Etot, diffEtot, diffRhoe[1], diffRhoe[2])
            end
        end

        if diffEtot < etot_conv_thr
            Nconverges = Nconverges + 1
        else  # reset Nconverges
            Nconverges = 0
        end

        if (Nconverges >= 2)
            if verbose
                @printf("SCF_potmix is converged in %d iterations\n", iterSCF)
            end
            break
        end
        
        Etot_old = Etot
        Rhoe_old = copy(Rhoe)

        # Mix potentials (Hartree and XC, separately)

        if mix_method == "broyden"
            mix_broyden!( Ham.potentials.Hartree, VHa_inp, betamix, iterSCF, mixdim, df_VHa, dv_VHa )
            mix_broyden!( Ham.potentials.XC, Vxc_inp, betamix, iterSCF, mixdim, df_Vxc, dv_Vxc )

        elseif mix_method == "linear_adaptive"
            mix_adaptive!( Ham.potentials.Hartree, VHa_inp, betamix, betav_VHa, df_VHa )
            mix_adaptive!( Ham.potentials.XC, Vxc_inp, betamix, betav_Vxc, df_Vxc )

        else
            # simple mixing
            Ham.potentials.Hartree = betamix*Ham.potentials.Hartree + (1-betamix)*VHa_inp
            Ham.potentials.XC = betamix*Ham.potentials.XC + (1-betamix)*Vxc_inp
        end


        # Don't forget to update the total local potential
        for ispin = 1:Nspin
            for ip = 1:Npoints
                Ham.potentials.Total[ip,ispin] = Ham.potentials.Ps_loc[ip] + Ham.potentials.Hartree[ip] +
                                                 Ham.potentials.XC[ip,ispin]
            end
        end

        flush(stdout)
    end

    if Nconverges < 2
        @printf("WARNING: SCF is not converged after %d iterations\n", NiterMax)
    end

    Ham.electrons.ebands = evals

    if use_smearing && verbose
        @printf("\nFermi energy = %18.10f Ha = %18.10f eV\n", E_fermi, E_fermi*2*Ry2eV)
    end

    if Nspin == 2 && verbose
        @printf("\n")
        @printf("Final integ Rhoe up  = %18.10f\n", sum(Rhoe[:,1])*dVol)
        @printf("Final integ Rhoe dn  = %18.10f\n", sum(Rhoe[:,2])*dVol)
        @printf("Final integ magn_den = %18.10f\n", sum(Rhoe[:,1] - Rhoe[:,2])*dVol)
    end

    if verbose && print_final_ebands
        @printf("\n")
        @printf("----------------------------\n")
        @printf("Final Kohn-Sham eigenvalues:\n")
        @printf("----------------------------\n")
        @printf("\n")
        print_ebands(Ham.electrons, Ham.pw.gvecw.kpoints)
    end

    if verbose && print_final_energies
        @printf("\n")
        @printf("-------------------------\n")
        @printf("Final Kohn-Sham energies:\n")
        @printf("-------------------------\n")
        @printf("\n")
        println(Ham.energies, use_smearing=use_smearing)
    end

    if savewfc
        for ikspin = 1:Nkpt*Nspin
            wfc_file = open("WFC_ikspin_"*string(ikspin)*".data","w")
            write( wfc_file, psiks[ikspin] )
            close( wfc_file )
        end
    end

    return
end