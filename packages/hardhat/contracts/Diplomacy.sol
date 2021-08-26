//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "prb-math/contracts/PRBMathSD59x18.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract Diplomacy is AccessControl, Ownable {
    using PRBMathSD59x18 for int256;
    using SafeMath for uint256;

    struct Election {
        string name; // Creator title/names/etc
        bool active; // Election status
		bool paid; //election is paid out
        uint256 createdAt; // Creation block time-stamp
        address[] candidates; // Candidates (who can vote/be voted)
        uint256 funds;
        uint256 votes;  // Number of votes delegated to each candidate
        address admin;
        mapping(address => bool) voted; // Voter status
        mapping(address => string[]) scores; // string of sqrt votes
        mapping(address => int256) results; // Voter to closed-election result 
    }

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    event BallotCast(
        address voter,
        uint256 electionId,
        address[] adrs,
        string[] scores
    );
    event ElectionCreated(address creator, uint256 electionId);
    event ElectionEnded(uint256 electionId);
    event ElectionPaid(uint256 electionId);

    bytes32 internal constant ELECTION_ADMIN_ROLE =
        keccak256("ELECTION_ADMIN_ROLE");
    bytes32 internal constant ELECTION_CANDIDATE_ROLE =
        keccak256("ELECTION_CANDIDATE_ROLE");

    modifier onlyContractAdmin() {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "Sender not Contract Admin!"
        );
        _;
    }

    modifier onlyElectionCandidate(uint256 electionId) {
        require(
            hasRole(ELECTION_CANDIDATE_ROLE, msg.sender),
            "Sender not Election Candidate!"
        );
        require(
            isElectionCandidate(electionId, msg.sender),
            "Sender not Election Candidate!"
        );
        _;
    }

    modifier onlyElectionAdmin(uint256 electionId) {
        require(
            hasRole(ELECTION_ADMIN_ROLE, msg.sender),
            "Sender not Election Admin!"
        );
        require(
            msg.sender == elections[electionId].admin,
            "Sender not Election Admin!"
        );
        _;
    }

    modifier validElectionVote(
        uint256 electionId,
        address[] memory _adrs,
        string[] memory _scores
    ) {
        require(elections[electionId].active, "Election Not Active!");
        require(
            !elections[electionId].voted[msg.sender],
            "Sender already voted!"
        );
        require ( _scores.length == _adrs.length, "Scores Candidate Count Mismatch!" );
        //require ( _scores.length == elections[electionId].votes, "Not enough votes sent!" );
        _;
    }

    uint256 public numElections;
    mapping(uint256 => Election) public elections;

    function newElection(
        string memory _name,
        uint256 _funds,
        uint256 _votes,
        address[] memory _adrs
    ) public returns (uint256 electionId) {

        electionId = numElections++;
        Election storage election = elections[electionId];
        election.name = _name;
        election.funds = _funds;
        election.votes = _votes;
        election.candidates = _adrs;
        election.createdAt = block.timestamp;
        election.active = true;
        election.admin = msg.sender;

        // Setup roles
        setElectionCandidateRoles(_adrs);
        setElectionAdminRole(msg.sender);

        emit ElectionCreated(msg.sender, electionId);
    }

    function castBallot(
        uint256 electionId,
        address[] memory _adrs,
        string[] memory _scores // sqrt of votes
    ) public onlyElectionCandidate(electionId) validElectionVote(electionId, _adrs, _scores) {

        Election storage election = elections[electionId];

        for (uint256 i = 0; i < _adrs.length; i++) {
            election.scores[_adrs[i]].push(_scores[i]); 
        }

        election.voted[msg.sender] = true;

        emit BallotCast(msg.sender, electionId, _adrs, _scores);
    }

    function endElection(uint256 electionId)
        public
        onlyElectionAdmin(electionId)
    {
        Election storage election = elections[electionId];

        require(election.active, "Election Already Ended!");

        election.active = false;

        emit ElectionEnded(electionId);
    }

    function payoutElection(
        uint256 electionId,
        address[] memory _adrs,
        uint256[] memory _pay
    ) public payable onlyElectionAdmin(electionId) {
        require(!elections[electionId].active, "Election Still Active!");

        uint256 paySum;
        for (uint256 i = 0; i < elections[electionId].candidates.length; i++) {
            require(
                elections[electionId].candidates[i] == _adrs[i],
                "Election-Address Mismatch!"
            );
            paySum += _pay[i];
        }

        //require( paySum >= elections[electionId].funds,  "Payout-Election Funds Mismatch!" );
        // require( msg.value == elections[electionId].funds, "Sender Payout-Funds Mismatch!" );

        for (uint256 i = 0; i < _pay.length; i++) {
            payable(_adrs[i]).transfer(_pay[i] * 1 wei);
        }

		elections[electionId].paid = true;

        emit ElectionPaid(electionId);
    }

    // Setters
    function setElectionCandidateRoles(address[] memory _adrs) internal {
        for (uint256 i = 0; i < _adrs.length; i++) {
            _setupRole(ELECTION_CANDIDATE_ROLE, _adrs[i]);
        }
    }

    function setElectionAdminRole(address adr) internal {
        _setupRole(ELECTION_ADMIN_ROLE, adr);
    }

    // Getters
    function getElectionById(uint256 electionId)
        public
        view
        returns (
            string memory name,
            address[] memory candidates,
            uint256 n_addr,
            uint256 createdAt,
            uint256 funds,
            uint256 votes,
            address admin,
            bool isActive,
			bool paid
        )
    {
        name = elections[electionId].name;
        candidates = elections[electionId].candidates;
        n_addr = elections[electionId].candidates.length;
        createdAt = elections[electionId].createdAt;
        funds = elections[electionId].funds;
        votes = elections[electionId].votes;
        admin = elections[electionId].admin;
        isActive = elections[electionId].active;
		paid = elections[electionId].paid;
    }

    function getElectionScores(uint256 electionId, address _adr)
        public
        view
        returns (string[] memory)
    {
        return elections[electionId].scores[_adr];
    }

    function getElectionResults(uint256 electionId, address _adr)
        public
        view
        returns (int256)
    {
        // require( !(elections[electionId].active), "Active election!" );
        return elections[electionId].results[_adr];
    }

    function getElectionVoted(uint256 electionId)
        public
        view
        returns (uint256 count)
    {
        for (uint256 i = 0; i < elections[electionId].candidates.length; i++) {
            address candidate = elections[electionId].candidates[i];
            if (elections[electionId].voted[candidate]) {
                count++;
            }
        }
    }

    function canVote(uint256 electionId, address _sender)
        public
        view
        returns (bool status)
    {
        for (uint256 i = 0; i < elections[electionId].candidates.length; i++) {
            address candidate = elections[electionId].candidates[i];
            if (_sender == candidate) {
                status = true;
            }
        }
    }

    function isElectionAdmin(uint256 electionId, address _sender)
        public
        view
        returns (bool)
    {
        return _sender == elections[electionId].admin;
    }

    function isElectionCandidate(uint256 electionId, address _sender)
        public
        view
        returns (bool status)
    {
        for (uint256 i = 0; i < elections[electionId].candidates.length; i++) {
            if (_sender == elections[electionId].candidates[i]) {
                status = true;
                break;
            }
        }
    }

    function hasVoted(uint256 electionId, address _sender)
        public
        view
        returns (bool)
    {
        return elections[electionId].voted[_sender];
    }
}
