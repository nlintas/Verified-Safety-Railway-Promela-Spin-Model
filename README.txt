Detailed Description:
    TerminalLine: Modelling and verifying a safe railway network. 

    * Intro *
    TerminalLine is a simple circular railway network that interconnects an airport’s 4 terminals through underground tunnels; each terminal is assumed to have a TerminalLine station.

    * Original Unsafe Network *
    Listing 1 provides a Promela model of TerminalLine. Observe that, whilst stations are modelled as processes, tunnels are modelled as channels; consequently, the movement of trains is modelled as message passing. A train takes the form of the symbolic constant train. A crash (unsafe state) corresponds to two trains occupying the same tunnel at the same moment in time. In other words, a crash corresponds to a tunnel channel being full at some moment of time.
    
    The model of Listing 1 is unsafe as it does not incorporate a signaling system; as a result, if two or more trains operate, the safety property whereby a tunnel can only be occupied by at most one train at a time will be eventually violated1. This property can be expressed in the provided model by the following system invariant:

    nfull(Tunnel_1_2) && nfull(Tunnel_2_3) && nfull(Tunnel_3_4) && nfull(Tunnel_4_1)

    Using SPIN’s verification capabilities, it can be easily demonstrated that this property is violated by Listing 1. Note that a two-train network, as modelled here, is sufficient to demonstrate that the system is unsafe. Note also that it is assumed that up to two trains can occupy a station at the same time, i.e. safety relates to tunnels only.

    * Requirements *

    You are required to extend the provided Promela model with a signaling system such that the safe passage of trains is guaranteed, i.e. the safety property above is satisfied. Your extended Promela model must adhere to the following requirements:

        1. No part of the original model can be removed: your design should only add additional elements to the original model.

        2. Each station should include a track-side signal that can either instruct trains to stop or proceed, i.e. can either instruct trains to remain in the station or proceed into the tunnel in advance of the station.

        3. Each track-side signal should be controlled by an associated signalbox.

        4. As depicted in Fig. 2, each signalbox should only be able to output messages to the signalbox to the
        rear of its position, and to input messages from the signalbox in advance of its position. For instance, the signalbox controlling the track-side signal at station 1 can only output messages to the signalbox controlling the track-side signal at station 4, and it can only input messages from the signalbox controlling the track-side signal at station 2.

        5. As depicted in Fig. 2, each signalbox can output messages to, and input messages from, its associated station, e.g. the signalbox controlling the track-side signal at station 1 can output messages to, and receive messages from, station 1.

        6. A station cannot communicate with any other station or with any signalbox associated with another
        station.

        7. A station and its associated signalbox can only observe trains as they arrive and depart; that is, they
        can only determine the status of the tunnels in advance and to the rear of the station by observing when a train leaves the tunnel to the rear (and enters the station area), and when a train enters the tunnel in advance (and leaves the station area).

        8. Each station should communicate to its associated signalbox the arrival and departure of a train.

        9. You are required to verify your system with respect to the safety property given in the Introduction. The verification should be done in two ways: through a system assertion and through an LTL property.

        10. You are also required to formulate in LTL a (desirable) liveness property of your choice that your system should satisfy, and verify it using SPIN.

        11. Your model should never terminate and should never deadlock.

        12. Your code must not make use of the Promela functions len, nfull, full, empty. These functions may, however, be used (if required) for formulating the system assertion and the LTL properties that are to be verified. Your code must not at any point use the atomic, d-step, or timeout operators.

Aims:
    ▪ Understand the merits and challenges associated with formal specification and verification of software systems
    ▪ Understand the strategies underpinning formal system verification
    ▪ Employ Promela for modelling concurrent systems
    ▪ Understand how to employ SPIN to model-check PROMELA processes

How to run:
    - Use the SPIN Model Checker and any text editor for inspecting the code (Only tested in Linux).