using PWDFT

function test_main( ; method="SCF" )

    #
    # Atoms
    #
    atoms = init_atoms_xyz("../structures/Be.xyz")
    println(atoms)

    #
    # Initialize Hamiltonian
    #
    pspfiles = ["../pseudopotentials/pade_gth/Be-q4.gth"]
    LatVecs = 16.0*diagm( ones(3) )
    ecutwfc_Ry = 30.0
    Ham = PWHamiltonian( atoms, pspfiles, ecutwfc_Ry*0.5, LatVecs )

    println("sum V Ps loc = ", sum(Ham.potentials.Ps_loc))

    # calculate E_NN
    Zvals = get_Zvals( Ham.pspots )
    Ham.energies.NN = calc_E_NN( Ham.pw, atoms, Zvals )

    println("\nAfter calculating E_NN")
    println(Ham.energies)

    if method == "SCF"
        λ, v = KS_solve_SCF!( Ham )
        println("\nAfter calling KS_solve_SCF:")

    elseif method == "Emin"
        λ, v = KS_solve_Emin_PCG!( Ham )
        println("\nAfter calling KS_solve_Emin_PCG:")

    elseif method == "DCM"
        λ, v = KS_solve_DCM!( Ham )
        println("\nAfter calling KS_solve_DCM:")

    else
        println("ERROR: unknow method = ", method)
    end

    Nstates = Ham.electrons.Nstates
    println("\nEigenvalues")
    for ist = 1:Nstates
        @printf("%8d  %18.10f = %18.10f eV\n", ist, λ[ist], λ[ist]*Ry2eV*2)
    end
    println("\nTotal energy components")
    println(Ham.energies)

end

@time test_main(method="Emin")
#@time test_main(method="DCM")
#@time test_main(method="SCF")

"""
-----------------------------------------------------------

Results from ABINIT 30 Ry with NL pspot (the usual one)
    Kinetic energy  =  3.56342013836996E-01
    Hartree energy  =  3.50397710827049E-01
    XC energy       = -3.67782685733863E-01
    Ewald energy    = -3.54662184935077E-01
    PspCore energy  = -1.39286404377276E-03
    Loc. psp. energy= -1.21257971730573E+00
    NL   psp  energy=  2.38145519069942E-01
    >>>>>>>>> Etotal= -9.91532208284459E-01

Total energy components
    Kinetic    energy:       0.3566282013
    Ps_loc     energy:      -1.2145559006
    Ps_nloc    energy:       0.2383401330
    Hartree    energy:       0.3506139979
    XC         energy:      -0.3679011972
    -------------------------------------
    Electronic energy:      -0.6368747655
    NN         energy:      -0.3546621849
    -------------------------------------
    Total      energy:      -0.9915369505    

-------------------------------------------------------

For Be-q4:
    Kinetic energy  =  6.88973511230564E+00
    Hartree energy  =  4.07042814114090E+00
    XC energy       = -1.86888469488722E+00
    Ewald energy    = -1.41864873974031E+00
    PspCore energy  = -1.04515099744636E-05
    Loc. psp. energy= -1.89190213862564E+01
    NL   psp  energy=  0.00000000000000E+00
    >>>>>>>>> Etotal= -1.12464020189474E+01

Be-qe PWSCF
!    total energy              =     -22.49244483 Ry = -11.246222415 Ha
     one-electron contribution =     -24.05999324 Ry
     hartree contribution      =       8.14249836 Ry
     xc contribution           =      -3.73765240 Ry
     ewald contribution        =      -2.83729755 Ry = 

Kinetic    energy:       6.8896455264
Ps_loc     energy:     -18.9192382235
Ps_nloc    energy:       0.0000000000
Hartree    energy:       4.0707738696
XC         energy:      -1.8697153278
-------------------------------------
Electronic energy:      -9.8285341553
NN         energy:      -1.4186487397
-------------------------------------
Total      energy:     -11.2471828950

"""
