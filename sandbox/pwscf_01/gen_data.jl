using Printf
using PWDFT

const DIR_PWDFT = joinpath(dirname(pathof(PWDFT)), "..")
const DIR_PSP = joinpath(DIR_PWDFT, "pseudopotentials", "pade_gth")
const DIR_STRUCTURES = joinpath(DIR_PWDFT, "structures")

include(joinpath(DIR_PWDFT, "sandbox", "ABINIT.jl"))
include(joinpath(DIR_PWDFT, "sandbox", "PWSCF.jl"))
include(joinpath(DIR_PWDFT, "sandbox", "KS_solve_SCF_potmix.jl"))

function init_Ham_Si_fcc( a::Float64, meshk::Array{Int64,1} )
    atoms = Atoms(xyz_string_frac=
        """
        2

        Si  0.0  0.0  0.0
        Si  0.25  0.25  0.25
        """, in_bohr=true, LatVecs=gen_lattice_fcc(a))

    pspfiles = [joinpath(DIR_PSP, "Si-q4.gth")]
    ecutwfc = 15.0
    return Hamiltonian( atoms, pspfiles, ecutwfc, meshk=meshk )
end

function main()

    LATCONST = 10.2631

    scal_i = 0.8
    scal_f = 1.2
    Ndata = 3
    Δ = (scal_f - scal_i)/(Ndata-1)
    
    stdout_orig = stdout

    f = open("TEMP_EOS_data.dat", "w")

    for i = 1:Ndata

        scal = scal_i + (i-1)*Δ

        a = LATCONST*scal

        fname = "TEMP_LOG_"*string(i)
        fileout = open(fname, "w")
        
        redirect_stdout(fileout)
    
        Ham = init_Ham_Si_fcc( a, [3,3,3] )
        KS_solve_SCF_potmix!( Ham )

        run(`rm -fv TEMP_abinit/\*`)
        write_abinit(Ham, prefix_dir="./TEMP_abinit/")
        cd("./TEMP_abinit")
        run(pipeline(`abinit`, stdin="FILES", stdout="ABINIT_o_LOG"))
        cd("../")

        abinit_energies = read_abinit_etotal("TEMP_abinit/LOG1")
        println("\nABINIT result\n")
        println(abinit_energies)

        run(`rm -rfv TEMP_pwscf/\*`)
        write_pwscf( Ham, prefix_dir="TEMP_pwscf" )
        cd("./TEMP_pwscf")
        run(pipeline(`pw.x`, stdin="PWINPUT", stdout="LOG1"))
        cd("../")

        pwscf_energies = read_pwscf_etotal("TEMP_pwscf/LOG1")
        println("\nPWSCF result\n")
        println(pwscf_energies)

        close(fileout)

        @printf(f, "%18.10f %18.10f %18.10f %18.10f\n", a, sum(Ham.energies),
                sum(abinit_energies), sum(pwscf_energies) )
    end

    close(f)

end

main()

