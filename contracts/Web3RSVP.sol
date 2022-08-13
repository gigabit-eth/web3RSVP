// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

contract Web3RSVP {
    event NewEventCreated(
        bytes32 eventID,
        address creatorAddress,
        uint256 eventTimestamp,
        uint256 maxCapacity,
        uint256 deposit,
        string eventDataCID
    );
    event NewRSVP(bytes32 eventID, address attendeeAddress);
    event ConfirmedAttendee(bytes32 eventID, address attendeeAddress);
    event DepositsPaidOut(bytes32 eventID);

    struct CreateEvent {
        bytes32 eventId;
        string eventDataCID;
        address eventOwner;
        uint256 eventTimestamp;
        uint256 deposit;
        uint256 maxCapacity;
        address[] confirmedRSVPs;
        address[] claimedRSVPs;
        bool paidOut;
    }

    mapping(bytes32 => CreateEvent) public idToEvent;

    function createNewEvent(
        uint256 eventTimestamp,
        uint256 deposit,
        uint256 maxCapacity,
        string calldata eventDataCID
    ) external {
        // This creates an eventId based on params passed in to generate a unique hash
        bytes32 eventId = keccak256(
            abi.encodePacked(
                msg.sender,
                address(this),
                eventTimestamp,
                deposit,
                maxCapacity
            )
        );

        address[] memory confirmedRSVPs;
        address[] memory claimedRSVPs;

        // This creates a new createEvent struct and adds it to the idToEvent mapping
        idToEvent[eventId] = CreateEvent(
            eventId,
            eventDataCID,
            msg.sender,
            eventTimestamp,
            deposit,
            maxCapacity,
            confirmedRSVPs,
            claimedRSVPs,
            false
        );

        // check to make sure this eventId is not already in use
        require(
            idToEvent[eventId].eventTimestamp == 0,
            "Event ID Already Exists"
        );

        emit NewEventCreated(
            eventId,
            msg.sender,
            eventTimestamp,
            maxCapacity,
            deposit,
            eventDataCID
        );
    }

    function createNewRSVP(bytes23 eventId) external payable {
        // look up event from our mapping
        CreateEvent storage myEvent = idToEvent[eventId];

        // transfer deposit to our contract address
        require(msg.value == myEvent.deposit, "Not Enough Deposit");

        // require that the event has not already happened
        require(
            block.timestamp <= myEvent.eventTimestamp,
            "Event Has Already Happened"
        );

        // make sure event is under max capacity
        require(
            myEvent.confirmedRSVPs.length < myEvent.maxCapacity,
            "The Event Is Full"
        );

        // require that msg.sender hasn't already RSVP'd
        for (uint8 i = 0; i < myEvent.confirmedRSVPs.length; i++) {
            require(
                myEvent.confirmedRSVPs[i] != msg.sender,
                "Already Confirmed!"
            );
        }

        myEvent.confirmedRSVPs.push(payable(msg.sender));

        emit NewRSVP(eventId, msg.sender);
    }

    function confirmAttendee(bytes32 eventId, address attendee) public {
        // look up event from our struct using th eventID
        CreateEvent storage myEvent = idToEvent[eventId];

        // require that msg.sender is the owner of the event
        require(msg.sender == myEvent.eventOwner, "NOT AUTHORIZED");

        // require that attendee actually RSVP'd
        address rsvpConfirm;

        for (uint8 i = 0; i < myEvent.confirmedRSVPs.length; i++) {
            if (myEvent.confirmedRSVPs[i] == attendee) {
                rsvpConfirm = myEvent.confirmedRSVPs[i];
            }
        }

        require(rsvpConfirm == attendee, "NO RSVP TO CONFIRM");

        // require the attendee is NOT already in the claimedRSVP list
        for (uint8 i = 0; i < myEvent.claimedRSVPs.length; i++) {
            require(myEvent.claimedRSVPs[i] != attendee, "ALREADY CLAIMED!");
        }

        // require that deposits are not already claimed by event owner
        require(myEvent.paidOut == false, "ALREADY PAID OUT");

        // add the attendee to the claimedRSVPs list
        myEvent.claimedRSVPs.push(attendee);

        // sending back the eth to the staker - https://solidity-by-example.org/sending-ether
        (bool sent, ) = attendee.call{value: myEvent.deposit}("");

        // if this fails remove the user from the array of claimedRSVPs
        if (!sent) {
            myEvent.claimedRSVPs.pop();
        }

        require(sent, "Failed to Send ETH");

        emit ConfirmedAttendee(eventId, attendee);
    }

    function confirmAllAttendees(bytes32 eventId) external {
        // look up event from our struct w/ eventId
        CreateEvent memory myEvent = idToEvent[eventId];

        // make sure you require msg.sender is the owner
        require(msg.sender == myEvent.eventOwner, "NOT AUTHORIZED");

        // confirm each attendee in the rsvp array
        for (uint8 i = 0; i < myEvent.confirmedRSVPs.length; i++) {
            confirmAttendee(eventId, myEvent.confirmedRSVPs[i]);
        }
    }

    function withdrawUnclaimedDeposits(bytes32 eventId) external {
        // look up the event
        CreateEvent memory myEvent = idToEvent[eventId];

        // check that the paidOut boolean still equals false
        require(!myEvent.paidOut, "ALREADY PAID");

        // check if it's been 7 days past myEvent.eventTimestamp
        require(
            block.timestamp >= (myEvent.eventTimestamp + 7 days),
            "TOO EARLY"
        );

        // only the event owner can withdraw
        require(msg.sender == myEvent.eventOwner, "MUST BE EVENT OWNER");

        // calculate how many people didn't claim
        uint256 unclaimed = myEvent.confirmedRSVPs.length -
            myEvent.claimedRSVPs.length;

        uint256 payout = unclaimed * myEvent.deposit;

        // mark as paid before sending to avoid reentrancy attack
        myEvent.paidOut = true;

        // send the payout to the owner
        (bool sent, ) = msg.sender.call{value: payout}("");

        // if this fails
        if (!sent) {
            myEvent.paidOut = false;
        }

        emit DepositsPaidOut(eventId);
    }
}
