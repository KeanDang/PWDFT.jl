mutable struct Energies
    Total::Float64
    Kinetic::Float64
    Ps_loc::Float64
    Ps_nloc::Float64
    Hartree::Float64
    XC::Float64
    NN::Float64
end

# Default: all zeroes
function Energies()
    return Energies(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
end

import Base.println
function println( energies::Energies )
    @printf("\n")
    @printf("Kinetic    energy: %18.10f\n", energies.Kinetic )
    @printf("Ps_loc     energy: %18.10f\n", energies.Ps_loc )
    @printf("Ps_nloc    energy: %18.10f\n", energies.Ps_nloc )
    @printf("Hartree    energy: %18.10f\n", energies.Hartree )
    @printf("XC         energy: %18.10f\n", energies.XC )
    @printf("-------------------------------------\n")
    E_elec = energies.Kinetic + energies.Ps_loc + energies.Ps_nloc +
             energies.Hartree + energies.XC
    @printf("Electronic energy: %18.10f\n", E_elec)
    @printf("NN         energy: %18.10f\n", energies.NN )
    @printf("-------------------------------------\n")
    @printf("Total      energy: %18.10f\n", energies.Total )
end