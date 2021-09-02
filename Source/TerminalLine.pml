#define train 99; /* A train is identified by a constant. */
// Definition p, checks if there is a crash at any point in any tunnel.
#define p (len(Tunnel_1_2) < 2 && len(Tunnel_2_3) < 2 && len(Tunnel_3_4) < 2 && len(Tunnel_4_1)  < 2);
// Definition q, checks if all stations when sending a request receive a proceed from signal boxes.
#define q (((station_to_signalbox1 == REQUEST) -> (signalbox_to_station1 == PROCEED)) && ((station_to_signalbox2 == REQUEST) -> (signalbox_to_station2 == PROCEED)) && ((station_to_signalbox3 == REQUEST) -> (signalbox_to_station3 == PROCEED)) && ((station_to_signalbox4 == REQUEST) -> (signalbox_to_station4 == PROCEED)));

chan Tunnel_1_2 = [2] of { byte }; /* Models tunnel between stations 1 and 2 */
chan Tunnel_2_3 = [2] of { byte }; /* Models tunnel between stations 2 and 3 */
chan Tunnel_3_4 = [2] of { byte }; /* Models tunnel between stations 3 and 4 */
chan Tunnel_4_1 = [2] of { byte }; /* Models tunnel between stations 4 and 1 */

// Signal boxes channels for communication.
chan signalbox1_2 = [0] of { mtype };
chan signalbox4_1 = [0] of { mtype };
chan signalbox2_3 = [0] of { mtype };
chan signalbox3_4 = [0] of { mtype };

// Signalbox to station channels and vice versa.
chan station_to_signalbox1 = [0] of { mtype };
chan signalbox_to_station1 = [0] of { mtype };

chan station_to_signalbox2 = [0] of { mtype };
chan signalbox_to_station2 = [0] of { mtype };

chan station_to_signalbox3 = [0] of { mtype };
chan signalbox_to_station3 = [0] of { mtype };

chan station_to_signalbox4 = [0] of { mtype };
chan signalbox_to_station4 = [0] of { mtype };
// Messages to be used and exchanged for station and signal box communications.
mtype = { ARRIVAL, REQUEST, DEPARTURE, TUNNEL_IS_EMPTY, PROCEED, DO_NOT_PROCEED }

/* Each station is modelled as a Promela process that takes as input the tunnel to the rear (i.e.
the in_track parameter), and the tunnel in advance (i.e. the out_track parameter); it also takes
as input the number of trains currently in the station (i.e. the train_cnt parameter).
*/

/*
"in_track" channel is the tunnel used for arriving trains.
"out_track" channel is the tunnel used for departing trains.
"signalBoxInput" channel is used for the station process to provide mtype messages to it's local signal box.
"signalBoxOutput" channel is used to receive mtype messages from the station's local signal box.
"train_cnt" is a byte parameter used for counting the amount of trains parked in station.
*/
proctype Station(chan in_track, out_track, signalBoxInput, signalBoxOutput; byte train_cnt)
{
    // Define the variable data type.
    mtype value;
    // The stations local traffic light, True = Green, False = Red.
    bool track_side_signal = false;

    /* The "do" loop repeatedly has the station process forever check for any new
    arriving trains from the "in_track" channel or if the station has any trains
    waiting with "train_cnt". */
    do
    /* If a train arrives "train_cnt" is incremented and an "ARRIVAL" message is
    sent to the station's track_side_signal box. */
    :: in_track?train -> signalBoxInput!ARRIVAL; train_cnt++;
    // Checks if any trains are waiting.
    :: (train_cnt > 0) ->
        if
        /* If the track_side_signal is true (i.e The traffic light is green) then
        the station sends a message to its signalbox informing it about the train's
        departure and a train is sent through the channel  with "train_cnt" being
        reduced by 1. */
        ::(track_side_signal == true) -> signalBoxInput!DEPARTURE; out_track!train; train_cnt--;
        /* If the track_side_signal is false (i.e The traffic light is red), the
        station sends a message to the signal box to request for permission to
        change its local signal. */
        ::(track_side_signal == false) ->signalBoxInput!REQUEST;
        fi;
        // Once the station sends one of the messages to the signalbox it waits for a reply.
        signalBoxOutput?value;
        if
        /* The signalbox replies with a "PROCEED" message, indicating the station
        is now allowed to change its track_side_signal to true. */
        ::(value == PROCEED) -> track_side_signal = true;
        /* The signalbox replies with a "DO_NOT_PROCEED" message, indicating the
        station is now allowed to change its track_side_signal to false. */
        ::(value == DO_NOT_PROCEED) -> track_side_signal = false;
        fi;
    od;
}

/* The SignalBox process is responsible for communicating with other signalboxes
in order to inform through channels its local and only station as to whether the
station should send or hold its currently parked trains. It is also informed from
the station whenever a train has departed or arrived so it performs accordingly.

"stationOutput" channel is used for receiving messages from the local station.
"stationInput" channel is used for providing messages to the local station.
"previousSignalBox" channel is used for sending messages to the previous signalbox of another station.
"fowardSignalBox" channel is used for receiving messages from the signalbox in the next station.
*/

proctype SignalBox(chan stationOutput, stationInput, previousSignalBox, forwardSignalBox)
{
    /* True = That the tunnel used to send trains for the local station is free
    and empty, False = That the tunnel is currently used to send trains for the
    local station is NOT free and empty. */
    bool trackIsFree = true;
    // Define the variable.
    mtype value;

    /* The "do" loop has the signalbox repeatedly check for arriving mtype messages
    from its local station or from the forward signal box. */
    do
    // Station sends a message through the channel.
    ::stationOutput?value
        if
        /* Station indicates the arrival of a train, the signal box informs the
        previous signal box that the tunnel is free. */
        ::(value == ARRIVAL) -> previousSignalBox!TUNNEL_IS_EMPTY;
        /* Station indicates the departure of one of its trains, "trackIsFree"
        is set to false to show this and the signal box sends a message to the
        station to set its local signal to false. */
        ::(value == DEPARTURE) -> trackIsFree = false; stationInput!DO_NOT_PROCEED;
        //Station requests for permission to change its local signal.
        ::(value == REQUEST) ->
            if
            /* The tunnel is free, the signalbox sends a message to the station
            allowing it to change its local signal to true. */
            ::(trackIsFree == true) -> stationInput!PROCEED;
            /* The tunnel is currently in use, the signalbox sends a message to
            the station informing it to wait and do nothing. */
            ::else -> stationInput!DO_NOT_PROCEED;
            fi
        fi;
    // The signal box found at the next station sends a message to this signal box.
    ::forwardSignalBox?value
        if
        /* If the tunnel this signal box is connected to is empty according to
        the message received, then trackIsFree is set to true. */
        ::(value == TUNNEL_IS_EMPTY) -> trackIsFree = true;
        fi;
    od;
}

/* The assert statement checks that no crashes occur in any of the tunnels by
making sure no more than one train uses the same tunnel at the same time. */
active proctype monitor()
{
    assert ((len(Tunnel_1_2) < 2 && len(Tunnel_2_3) < 2 && len(Tunnel_3_4) < 2 && len(Tunnel_4_1) < 2));
}

init
{
    atomic
    {
        // Process creation and channel mapping
        // The process that models station 1.
        run Station(Tunnel_4_1, Tunnel_1_2, station_to_signalbox1, signalbox_to_station1, 0);
        // The process that models station 2.
        run Station(Tunnel_1_2, Tunnel_2_3, station_to_signalbox2, signalbox_to_station2, 1);
        // The process that models station 3.
        run Station(Tunnel_2_3, Tunnel_3_4,  station_to_signalbox3, signalbox_to_station3, 0);
        // The process that models station 4.
        run Station(Tunnel_3_4, Tunnel_4_1,  station_to_signalbox4, signalbox_to_station4, 1);

        // The process that models signal box 1.
        run SignalBox(station_to_signalbox1, signalbox_to_station1, signalbox4_1, signalbox1_2);
        // The process that models signal box 2.
        run SignalBox(station_to_signalbox2, signalbox_to_station2, signalbox1_2, signalbox2_3);
        // The process that models signal box 3.
        run SignalBox(station_to_signalbox3, signalbox_to_station3, signalbox2_3, signalbox3_4);
        // The process that models signal box 4.
        run SignalBox(station_to_signalbox4, signalbox_to_station4, signalbox3_4, signalbox4_1);
    }
}

// ltl formula p1 makes sure definition p is always true (safety property).
ltl p1 { always p }
// ltl formula p2 makes sure definition q is always eventually true (liveness property)
ltl p2 { always eventually q }
