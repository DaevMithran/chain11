// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IChain11 {
    
    enum ContestState {
        Open,
        Locked,
        Settled
    }

    enum PlayerRole {
        Batsman,
        Bowler,
        AllRounder,
        WicketKeeper
    }
    
    enum RequestType {
        InitializeMatch,
        FetchScores,
        SettleContest
    }

    // Structs
    
    // Contest Data
    struct Contest {
        uint256 contestId;
        string matchId;
        address creator;
        uint256 createdAt;
        uint256 deadline;
        uint256 maxParticipants;
        uint256 prizePool;
        uint256 platformFeeCollected;
        ContestState state;
        address[] participants;
        mapping(address => bool) hasJoined;
        mapping(address => Team) teams;
        address[] winners;
        mapping(address => uint256) claimableWinnings;
    }
    
    // User's team info
    struct Team {
        uint256[] playerIds;
        uint256 captainId;
        uint256 viceCaptainId;
        int256 finalScore;
    }

    // User Functions    
    function createContest(
        string calldata cricketApiMatchId,
        uint256 deadline,
        uint256 maxParticipants
    ) external payable returns (uint256 contestId);
    
    function joinAndSubmitTeam(
        uint256 contestId,
        uint256[] calldata playerIds,
        uint256 captainId,
        uint256 viceCaptainId
    ) external payable;
    
    function lockContest(uint256 contestId) external;
    
    function settleContest(uint256 contestId) external;
    
    function claimPrize(uint256 contestId) external;
    
    // Oracle Callback
    
    function finalizeSettlement(
        uint256 contestId,
        address[] calldata winners,
        int256[] calldata scores
    ) external;
    
    // View
    
    function getContest(uint256 contestId) external view returns (
        string memory matchId,
        address creator,
        uint256 prizePool,
        uint256 participantCount,
        uint256 maxParticipants,
        ContestState state,
        uint256 deadline
    );
    
    function getTeam(uint256 contestId, address user) external view returns (
        uint256[] memory playerIds,
        uint256 captainId,
        uint256 viceCaptainId,
        int256 finalScore
    );
    
    function getParticipants(uint256 contestId) external view returns (address[] memory);
    
    function getTeamData(uint256 contestId, address user) external view returns (
        uint256[] memory playerIds,
        uint256 captainId,
        uint256 viceCaptainId
    );
}