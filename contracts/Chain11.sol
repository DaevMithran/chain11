// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IChain11} from "./IChain11.sol";
import {Chain11Oracle} from "./Chain11Oracle.sol";
/**
 * @title Chain11
 * @notice Decentralized fantasy cricket platform using Chainlink
 * 
 * Key Features:
 * - Users create contests by paying fee
 * - Chainlink fetches match data (trustless)
 * - Match data shared across all contests
 * - Join + submit team in one transaction
 * - Score fetching via Chainlink (once per match)
 * - Settlement on-chain (once per contest, efficient)
 */
contract Chain11 is IChain11 {    
    // Chainlink

    bytes32 public immutable donId;
    uint64 public subscriptionId;
    uint32 public constant GAS_LIMIT = 300000;
    
    // Constants
    
    uint256 public constant CONTEST_CREATION_FEE = 0.01 ether;
    uint256 public constant PLATFORM_FEE_BASIS_POINTS = 1000;
    uint256 public constant MAXIMUM_PARTICIPANTS_PER_ROOM = 500;
    
    // Rules

    uint256 public constant TEAM_SIZE = 11;
    uint256 public constant MIN_BATSMEN = 3;
    uint256 public constant MAX_BATSMEN = 6;
    uint256 public constant MIN_BOWLERS = 3;
    uint256 public constant MAX_BOWLERS = 6;
    uint256 public constant MIN_ALL_ROUNDERS = 1;
    uint256 public constant MAX_ALL_ROUNDERS = 4;
    uint256 public constant MIN_WICKET_KEEPERS = 1;
    uint256 public constant MAX_WICKET_KEEPERS = 4;
    uint256 public constant MIN_FROM_ONE_TEAM = 4;
    uint256 public constant MAX_FROM_ONE_TEAM = 7;
    uint256 public constant MAX_CREDITS = 100;
    uint256 public constant PLATFORM_FEE_PERCENT = 10;
    uint256 public constant MIN_PARTICIPANTS = 3;

    struct TeamCounts {
        uint256 batsmen;
        uint256 bowlers;
        uint256 allRounders;
        uint256 wicketKeepers;
        uint256 fromTeamA;
        uint256 totalCredits;
    }

    // State
    address public admin;
    Chain11Oracle public chain11Oracle;
    uint256 public nextContestId;
        
    // Contest ID => Contest data
    mapping(uint256 => Contest) public contests;
    
    // Match ID => Contest IDs (for discovery)
    mapping(string => uint256[]) public matchContests;
    
    // Events
    
    event MatchInitializationRequested(
        string indexed matchId,
        bytes32 indexed requestId,
        address indexed creator
    );
    
    event MatchInitialized(
        string indexed matchId,
        string teamAName,
        string teamBName
    );
    
    event ContestCreated(
        uint256 indexed contestId,
        string indexed matchId,
        address indexed creator,
        uint256 creationFee,
        uint256 maxParticipants,
        uint256 deadline
    );
    
    event UserJoinedAndSubmittedTeam(
        uint256 indexed contestId,
        address indexed user,
        uint256 amount,
        uint256[] playerIds
    );
    
    event ContestLocked(uint256 indexed contestId);
    
    event ScoreFetchRequested(
        string indexed matchId,
        bytes32 indexed requestId,
        address requester
    );

    event MatchScoresFinalized(
        string indexed matchId,
        uint256 playerCount,
        uint256 timestamp
    );

    event SettlementRequested(
        uint256 indexed contestId,
        string indexed matchId
    );
    
    event ContestSettled(
        uint256 indexed contestId,
        address[] winners,
        uint256 prizePool,
        uint256 timestamp
    );
    
    event PrizeClaimed(
        uint256 indexed contestId,
        address indexed winner,
        uint256 amount
    );

    event PlatformFeeWithdrawn(
        uint256 indexed contestId,
        uint256 amount
    );
    
    event ChainlinkRequestFailed(bytes32 indexed requestId, bytes error);
    
    // Errors
    
    error MatchNotInitialized();
    error MatchAlreadyStarted();
    error MatchNotCompleted();
    error ScoresNotFinalized();
    error ContestNotFound();
    error AlreadyJoined();
    error ContestFull();
    error IncorrectFee();
    error DeadlinePassed();
    error DeadlineNotPassed();
    error InvalidTeam();
    error ContestNotLocked();
    error ContestNotSettled();
    error NoWinnings();
    error TransferFailed();
    error Unauthorized();
    error InsufficientParticipants();
    error ZeroAddress();

    // Modifiers
    modifier onlyAdmin() {
        require(msg.sender == admin, Unauthorized());
        _;
    }

    modifier onlyOracle() {
        require(msg.sender == address(chain11Oracle), Unauthorized());
        _;
    }

    // Constructor
    constructor(address _chain11Oracle) {
        require(_chain11Oracle != address(0), ZeroAddress());
        admin = msg.sender;
        chain11Oracle = Chain11Oracle(_chain11Oracle);
    }
    
    // External
    
    /**
     * @notice User creates a contest for a match
     * @dev Triggers Chainlink to fetch match data if not initialized
     * @param cricketApiMatchId External API match ID
     * @param deadline Team submission deadline
     * @param maxParticipants Maximum number of participants
     */
    function createContest(
        string calldata cricketApiMatchId,
        uint256 deadline,
        uint256 maxParticipants
    ) external payable returns (uint256 contestId) {
        require(msg.value == CONTEST_CREATION_FEE, IncorrectFee());
        require(deadline > block.timestamp, "Invalid deadline");
        require(maxParticipants >= 3 && maxParticipants <= 600, "Invalid max");
        
        // Generate internal match ID
        string memory matchId = string(abi.encodePacked(cricketApiMatchId));
        
        if (!chain11Oracle.isMatchInitialized(cricketApiMatchId)) {
            chain11Oracle.initializeMatch(cricketApiMatchId);
        }

        // Create contest
        contestId = nextContestId++;
        Contest storage contest = contests[contestId];
        
        contest.contestId = contestId;
        contest.matchId = matchId;
        contest.creator = msg.sender;
        contest.createdAt = block.timestamp;
        contest.deadline = deadline;
        contest.maxParticipants = maxParticipants;
        contest.state = ContestState.Open;
        
        // Creation fee goes to prize pool
        uint256 platformFee = (msg.value * PLATFORM_FEE_BASIS_POINTS) / 10000;
        contest.prizePool = msg.value - platformFee;
        contest.platformFeeCollected = platformFee;
        
        // Track contest
        matchContests[matchId].push(contestId);
        
        emit ContestCreated(contestId, matchId, msg.sender, msg.value, maxParticipants, deadline);
        
        return contestId;
    }
        
    /**
     * @notice Join contest and submit team in ONE transaction
     * @dev Simplified UX - fewer edge cases
     */
    function joinAndSubmitTeam(
        uint256 contestId,
        uint256[] calldata playerIds,
        uint256 captainId,
        uint256 viceCaptainId
    ) external payable {
        Contest storage contest = contests[contestId];
        require(contest.contestId == contestId, ContestNotFound());
        require(contest.state == ContestState.Open, "Contest not open");
        require(block.timestamp < contest.deadline, DeadlinePassed());
        require(!contest.hasJoined[msg.sender], AlreadyJoined());
        require(contest.participants.length < contest.maxParticipants, ContestFull());
        require(msg.value == CONTEST_CREATION_FEE, IncorrectFee());
        
        // Validate team
        _validateTeam(contest.matchId, playerIds, captainId, viceCaptainId);
        
        // Split fee
        uint256 platformFee = (msg.value * PLATFORM_FEE_BASIS_POINTS) / 10000;
        contest.prizePool += msg.value - platformFee;
        contest.platformFeeCollected += platformFee;
        
        // Add participant
        contest.participants.push(msg.sender);
        contest.hasJoined[msg.sender] = true;
        
        // Store team
        contest.teams[msg.sender] = Team({
            playerIds: playerIds,
            captainId: captainId,
            viceCaptainId: viceCaptainId,
            finalScore: 0
        });
        
        emit UserJoinedAndSubmittedTeam(contestId, msg.sender, msg.value, playerIds);
    }

    /**
     * @notice Lock contest after deadline (permissionless)
     */
    function lockContest(uint256 contestId) external {
        Contest storage contest = contests[contestId];
        require(contest.state == ContestState.Open, "Not open");
        require(block.timestamp >= contest.deadline, "Deadline not passed");
        require(contest.participants.length >= 3, "Need min 3 participants");
        
        contest.state = ContestState.Locked;
        
        emit ContestLocked(contestId);
    }

    /**
     * @notice Request settlement from Oracle
     * @dev Oracle will compute winners off-chain via Chainlink and callback
     * @param contestId Contest to settle
     */
    function settleContest(uint256 contestId) external {
        Contest storage contest = contests[contestId];
        require(contest.state == ContestState.Locked, ContestNotLocked());
        
        string memory matchId = contest.matchId;
        require(chain11Oracle.isMatchCompleted(matchId), MatchNotCompleted());
        
        if (contest.participants.length < 3) revert InsufficientParticipants();
        
        chain11Oracle.requestSettlement(contestId, matchId);
        
        emit SettlementRequested(contestId, matchId);
    }

    /**
     * @notice Finalize settlement with winners from Oracle
     * @dev Called by Oracle contract after off-chain Chainlink computation
     * @param contestId Contest ID
     * @param winners Top K winner addresses (sorted by rank)
     * @param scores Winner scores
     */
    function finalizeSettlement(
        uint256 contestId,
        address[] calldata winners,
        int256[] calldata scores
    ) external onlyOracle {
        Contest storage contest = contests[contestId];
        
        require(contest.state == ContestState.Locked, "Not locked");
        require(winners.length >= 3 && winners.length <= 10, "Invalid count");
        require(winners.length == scores.length, "Length mismatch");
        
        // Determine prize structure
        bool useTopTen = contest.participants.length >= 10;
        uint256 pool = contest.prizePool;
        
        // Store winners and distribute prizes
        for (uint256 i = 0; i < winners.length;) {
            address winner = winners[i];
            
            // Verify winner is a participant
            require(contest.hasJoined[winner], "Invalid winner");
            
            // Store final score
            contest.teams[winner].finalScore = scores[i];
            
            // Calculate prize
            uint256 prize = _getPrizeForRank(i, pool, useTopTen);
            
            // Store claimable prize
            contest.claimableWinnings[winner] = prize;
            
            // Add to winners list
            contest.winners.push(winner);
            
            unchecked { i++; }
        }
        
        contest.state = ContestState.Settled;
        
        emit ContestSettled(contestId, winners, pool, block.timestamp);
    }

    
    /**
     * @notice Claim prize
     */
    function claimPrize(uint256 contestId) external {
        Contest storage contest = contests[contestId];
        require(contest.state == ContestState.Settled, ContestNotSettled());
        
        uint256 amount = contest.claimableWinnings[msg.sender];
        require(amount > 0, NoWinnings());
        
        contest.claimableWinnings[msg.sender] = 0;
        
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, TransferFailed());
        
        emit PrizeClaimed(contestId, msg.sender, amount);
    }
    
   // View
    /**
     * @notice Get contest details
     */
    function getContest(uint256 contestId) external view returns (
        string memory matchId,
        address creator,
        uint256 prizePool,
        uint256 participantCount,
        uint256 maxParticipants,
        ContestState state,
        uint256 deadline
    ) {
        Contest storage contest = contests[contestId];
        return (
            contest.matchId,
            contest.creator,
            contest.prizePool,
            contest.participants.length,
            contest.maxParticipants,
            contest.state,
            contest.deadline
        );
    }
    
    /**
     * @notice Get user's team
     */
    function getTeam(uint256 contestId, address user) external view returns (
        uint256[] memory playerIds,
        uint256 captainId,
        uint256 viceCaptainId,
        int256 finalScore
    ) {
        Contest storage contest = contests[contestId];
        Team storage team = contest.teams[user];
        return (
            team.playerIds,
            team.captainId,
            team.viceCaptainId,
            team.finalScore
        );
    }

    /**
     * @notice Get participants (called by Oracle settlement script)
     */
    function getParticipants(uint256 contestId) 
        external view returns (address[] memory) 
    {
        return contests[contestId].participants;
    }

    /**
     * @notice Get team data (called by Oracle settlement script)
     */
    function getTeamData(uint256 contestId, address user) 
        external view returns (
            uint256[] memory playerIds,
            uint256 captainId,
            uint256 viceCaptainId
        ) 
    {
        Team storage team = contests[contestId].teams[user];
        return (team.playerIds, team.captainId, team.viceCaptainId);
    }
    
    /**
     * @notice Get all contests for a match
     */
    function getMatchContests(string calldata matchId) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return matchContests[matchId];
    }
    
    /**
     * @notice Get contest winners
     */
    function getWinners(uint256 contestId) 
        external 
        view 
        returns (address[] memory) 
    {
        return contests[contestId].winners;
    }
    
    /**
     * @notice Get user's claimable winnings
     */
    function getClaimableWinnings(uint256 contestId, address user) 
        external 
        view 
        returns (uint256) 
    {
        return contests[contestId].claimableWinnings[user];
    }

    // Internal
    function _validateTeam(
        string memory matchId,
        uint256[] calldata playerIds,
        uint256 captainId,
        uint256 viceCaptainId
    ) internal view {
        require(playerIds.length == TEAM_SIZE, InvalidTeam());
        require(captainId != viceCaptainId, InvalidTeam());
        
        require(chain11Oracle.isMatchUpcoming(matchId), MatchAlreadyStarted());
                
        (
            uint256[] memory ids,
            uint8[] memory roles,
            uint8[] memory teams,
            uint8[] memory credits
        ) = chain11Oracle.getPlayers(matchId, playerIds);

        bool captainFound = false;
        bool viceCaptainFound = false;        
        // Validate composition
        TeamCounts memory counts;
        unchecked {
            for (uint256 i = 0; i < TEAM_SIZE; i++) {
                // Validate captain/VC in team
                if (playerIds[i] == captainId) captainFound = true;
                if (playerIds[i] == viceCaptainId) viceCaptainFound = true;

                // Check duplicates playerIds
                for (uint256 j = i + 1; j < TEAM_SIZE; j++) {
                    require(playerIds[i] != playerIds[j], InvalidTeam());
                }

                if (ids[i] == 0) revert InvalidTeam();

                // Count roles
                if (roles[i] == 0) counts.batsmen++;
                else if (roles[i] == 1) counts.bowlers++;
                else if (roles[i] == 2) counts.allRounders++;
                else if (roles[i] == 3) counts.wicketKeepers++;
                
                // Count teams
                if (teams[i] == 0) counts.fromTeamA++;
                
                // Sum credits
                counts.totalCredits += credits[i];
            }
        }

        require(captainFound && viceCaptainFound, InvalidTeam());

        
        // Validate constraints
        require(counts.batsmen >= MIN_BATSMEN && counts.batsmen <= MAX_BATSMEN, InvalidTeam());
        require(counts.bowlers >= MIN_BOWLERS && counts.bowlers <= MAX_BOWLERS, InvalidTeam());
        require(counts.allRounders >= MIN_ALL_ROUNDERS && counts.allRounders <= MAX_ALL_ROUNDERS, InvalidTeam());
        require(counts.wicketKeepers >= MIN_WICKET_KEEPERS && counts.wicketKeepers <= MAX_WICKET_KEEPERS, InvalidTeam());
        require(counts.fromTeamA >= MIN_FROM_ONE_TEAM && counts.fromTeamA <= MAX_FROM_ONE_TEAM, InvalidTeam());
        require(counts.totalCredits <= MAX_CREDITS, InvalidTeam());
    }

    
    // Helpers
    function _getPrizeForRank(uint256 rank, uint256 pool, bool topTen) 
        internal 
        pure 
        returns (uint256) 
    {
        if (topTen) {
            if (rank == 0) return (pool * 30) / 100;      // 30%
            if (rank == 1) return (pool * 15) / 100;      // 15%
            if (rank == 2) return (pool * 10) / 100;      // 10%
            if (rank >= 3 && rank <= 9) return (pool * 5) / 100;  // 5% each
        } else {
            if (rank == 0) return (pool * 50) / 100;      // 50%
            if (rank == 1) return (pool * 30) / 100;      // 30%
            if (rank == 2) return (pool * 20) / 100;      // 20%
        }
        return 0;
    }

    // Admin
    function updateOracle(address newOracle) external onlyAdmin {
        require(newOracle != address(0), "Zero address");
        chain11Oracle = Chain11Oracle(newOracle);
    }

    function transferAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "Zero address");
        admin = newAdmin;
    }
}

