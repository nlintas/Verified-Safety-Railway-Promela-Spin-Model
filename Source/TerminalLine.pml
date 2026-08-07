/*
 * TerminalLine: a four-station circular railway.
 *
 * A buffered tunnel channel contains one TRAIN message for each train that
 * is currently inside that tunnel.  A tunnel capacity of two is deliberate:
 * it leaves room for SPIN to represent the unsafe state (two trains in one
 * tunnel) instead of making the channel capacity enforce the property.
 */

#define TRAIN 99
#define TOTAL_TRAINS 2

/* Safety means that no tunnel ever contains two trains. */
#define SAFE (len(Tunnel_1_2) < 2 && len(Tunnel_2_3) < 2 && len(Tunnel_3_4) < 2 && len(Tunnel_4_1) < 2)

/*
 * These variables are observations, not extra control channels.  A station
 * sets its flag before requesting permission and clears it after the matching
 * PROCEED or DO_NOT_PROCEED response.  Thus an LTL claim can express
 * request/response progress without inspecting a rendezvous channel.
 */
bool request_pending[4];

/* Expensive shared observations are enabled only for consistency verification. */
#ifdef EXPANDED_VERIFY
bool block_reserved[4];
#endif

chan Tunnel_1_2 = [2] of { byte }; /* tunnel from station 1 to station 2 */
chan Tunnel_2_3 = [2] of { byte }; /* tunnel from station 2 to station 3 */
chan Tunnel_3_4 = [2] of { byte }; /* tunnel from station 3 to station 4 */
chan Tunnel_4_1 = [2] of { byte }; /* tunnel from station 4 to station 1 */

/* Every physically occupied tunnel must have been reserved by its rear box. */
#ifdef EXPANDED_VERIFY
#define OCCUPANCY_IS_RESERVED \
    ((len(Tunnel_1_2) == 0 || block_reserved[0]) && \
     (len(Tunnel_2_3) == 0 || block_reserved[1]) && \
     (len(Tunnel_3_4) == 0 || block_reserved[2]) && \
     (len(Tunnel_4_1) == 0 || block_reserved[3]))
#endif

/*
 * Signal-box links are directed by their argument position.  For example,
 * signalbox1_2 carries messages from box 2 (the box in advance) to box 1
 * (the box to the rear).  Two-place buffers preserve the communication
 * topology while preventing arrival notifications from blocking a signal box
 * that is currently answering a local request.  Two is enough for the two
 * trains in this model; increase it with the train bound when scaling up.
 */
chan signalbox1_2 = [2] of { mtype };
chan signalbox4_1 = [2] of { mtype };
chan signalbox2_3 = [2] of { mtype };
chan signalbox3_4 = [2] of { mtype };

/*
 * Local channels remain rendezvous channels: a station must synchronize its
 * request/departure with its own signal box and then wait for the response.
 */
chan station_to_signalbox1 = [0] of { mtype };
chan signalbox_to_station1 = [0] of { mtype };
chan station_to_signalbox2 = [0] of { mtype };
chan signalbox_to_station2 = [0] of { mtype };
chan station_to_signalbox3 = [0] of { mtype };
chan signalbox_to_station3 = [0] of { mtype };
chan station_to_signalbox4 = [0] of { mtype };
chan signalbox_to_station4 = [0] of { mtype };

mtype = { ARRIVAL, REQUEST, DEPARTURE, TUNNEL_IS_EMPTY, PROCEED, DO_NOT_PROCEED };

/*
 * A station observes only its rear and forward tunnel through channel events:
 * receiving TRAIN means arrival; sending TRAIN means departure.  It never
 * reads tunnel length or communicates with another station directly.
 *
 * station_id is 1..4 and is used only to index the LTL observation flags.
 */
proctype Station(chan in_track, out_track, signalBoxInput, signalBoxOutput;
                 byte train_cnt, station_id)
{
    mtype value;
    bool track_side_signal = false; /* false = stop, true = proceed */

    do
    :: in_track?TRAIN ->
        /* The tunnel is already empty at this point; notify the rear box. */
        signalBoxInput!ARRIVAL;
#ifdef EXPANDED_VERIFY
        assert(train_cnt < TOTAL_TRAINS);
#endif
        train_cnt++

    :: (train_cnt > 0) ->
        if
        :: track_side_signal ->
            /*
             * The box records the outgoing tunnel as occupied before this
             * rendezvous completes.  The assertion is placed immediately
             * after the channel send, where occupancy can increase.
             */
#ifdef EXPANDED_VERIFY
            assert(!block_reserved[station_id - 1]);
            block_reserved[station_id - 1] = true;
#endif
            signalBoxInput!DEPARTURE;
            out_track!TRAIN;
            assert(SAFE);
            train_cnt--

        :: !track_side_signal ->
#ifdef EXPANDED_VERIFY
            assert(!request_pending[station_id - 1]);
#endif
            request_pending[station_id - 1] = true;
            signalBoxInput!REQUEST
        fi;

        /* Every station request has exactly one response. */
        signalBoxOutput?value;
        if
        :: (value == PROCEED) ->
#ifdef EXPANDED_VERIFY
            assert(!track_side_signal);
#endif
            track_side_signal = true;
            request_pending[station_id - 1] = false
        :: (value == DO_NOT_PROCEED) ->
            track_side_signal = false;
            /* This attempt was answered; a retry creates a new pending pulse. */
            request_pending[station_id - 1] = false
#ifdef EXPANDED_VERIFY
        :: else ->
            /* Only response messages are valid on a box-to-station link. */
            assert(false)
#endif
        fi
    od
}

/*
 * A signal box owns one station signal and one outgoing tunnel reservation.
 * block_reserved changes only along the authorized departure/release path;
 * the box never reads a tunnel channel directly.
 */
proctype SignalBox(chan stationOutput, stationInput,
                   previousSignalBox, forwardSignalBox; byte block_id)
{
    bool trackIsFree = true;
    mtype value;

    do
    :: stationOutput?value ->
        if
        :: (value == ARRIVAL) ->
            /* The arriving station reports that this box's rear tunnel is free. */
            previousSignalBox!TUNNEL_IS_EMPTY

        :: (value == DEPARTURE) ->
            /* Reserve before the train is placed in the outgoing tunnel. */
#ifdef EXPANDED_VERIFY
            assert(trackIsFree);
            assert(block_reserved[block_id]);
#endif
            trackIsFree = false;
            stationInput!DO_NOT_PROCEED

        :: (value == REQUEST) ->
            if
            :: trackIsFree ->
#ifdef EXPANDED_VERIFY
                assert(!block_reserved[block_id]);
#endif
                stationInput!PROCEED
            :: else -> stationInput!DO_NOT_PROCEED
            fi
#ifdef EXPANDED_VERIFY
        :: else ->
            /* Inter-box messages are invalid on a station-to-box link. */
            assert(false)
#endif
        fi

    :: forwardSignalBox?value ->
        if
        :: (value == TUNNEL_IS_EMPTY) ->
#ifdef EXPANDED_VERIFY
            assert(!trackIsFree);
            assert(block_reserved[block_id]);
#endif
            trackIsFree = true;
#ifdef EXPANDED_VERIFY
            block_reserved[block_id] = false
#endif
#ifdef EXPANDED_VERIFY
        :: else ->
            assert(false)
#endif
        fi
    od
}

/*
 * The monitor has no enabled transition in a safe state.  If an unsafe state
 * is reached, its assertion transition is enabled and fails.  This preserves
 * SPIN's invalid-end-state/deadlock detection; an always-enabled monitor
 * loop would otherwise mask a deadlock in the railway protocol.
 */
active proctype monitor()
{
    do
    :: !SAFE -> assert(SAFE)
    od
}

init
{
    /*
     * No atomic block is used: requirement 12 forbids atomic/d_step.  Process
     * creation is still safe because every process that may rendezvous is
     * eventually created, and the station/signal-box loops never terminate.
     */
    run Station(Tunnel_4_1, Tunnel_1_2, station_to_signalbox1,
                signalbox_to_station1, 0, 1);
    run Station(Tunnel_1_2, Tunnel_2_3, station_to_signalbox2,
                signalbox_to_station2, 1, 2);
    run Station(Tunnel_2_3, Tunnel_3_4, station_to_signalbox3,
                signalbox_to_station3, 0, 3);
    run Station(Tunnel_3_4, Tunnel_4_1, station_to_signalbox4,
                signalbox_to_station4, 1, 4);

    run SignalBox(station_to_signalbox1, signalbox_to_station1,
                  signalbox4_1, signalbox1_2, 0);
    run SignalBox(station_to_signalbox2, signalbox_to_station2,
                  signalbox1_2, signalbox2_3, 1);
    run SignalBox(station_to_signalbox3, signalbox_to_station3,
                  signalbox2_3, signalbox3_4, 2);
    run SignalBox(station_to_signalbox4, signalbox_to_station4,
                  signalbox3_4, signalbox4_1, 3)
}

/* Safety claim: no tunnel can contain two trains. */
ltl p1 { [] SAFE }

/* Consistency claim: physical occupancy is always backed by a reservation. */
#ifdef EXPANDED_VERIFY
ltl p3 { [] OCCUPANCY_IS_RESERVED }
#endif

/*
 * Response claim: every accepted request eventually receives either response.
 * This is checked with weak process fairness because an otherwise-unfair
 * scheduler may indefinitely postpone an enabled rendezvous response.
 */
ltl p4 {
    [] ((request_pending[0] -> <> !request_pending[0]) &&
        (request_pending[1] -> <> !request_pending[1]) &&
        (request_pending[2] -> <> !request_pending[2]) &&
        (request_pending[3] -> <> !request_pending[3]))
}

/*
 * Liveness claim: from the initial configuration, a train eventually enters
 * a tunnel.  This is a finite, directly observable progress obligation that
 * can be checked exhaustively without relying on a scheduler fairness
 * assumption.  The request_pending flags above remain available for a
 * stronger per-request response claim in a larger/fairness-aware run.
 */
#define TRAIN_IN_TUNNEL (len(Tunnel_1_2) > 0 || len(Tunnel_2_3) > 0 || len(Tunnel_3_4) > 0 || len(Tunnel_4_1) > 0)
ltl p2 { <> TRAIN_IN_TUNNEL }
