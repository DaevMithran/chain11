// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/Strings.sol";
import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";

contract Chain11Oracle is FunctionsClient {
    using FunctionsRequest for FunctionsRequest.Request;
    using Strings for uint256;
    using Strings for address;

    // Chainlink Config
    bytes32 public immutable donId;
    uint64 public subscriptionId;
    uint32 public constant GAS_LIMIT = 700000;
    uint8 public constant SECRETS_SLOT_ID = 0;
    uint256 public constant TEAM_SIZE = 11;

   // enums
    enum MatchStatus {
        NotInitialized,
        Upcoming,
        Live,
        Completed
    }
    
    enum PlayerRole {
        Batsman,
        Bowler,
        AllRounder,
        WicketKeeper
    }
    
    enum TeamSide {
        TeamA,
        TeamB
    }
    
    enum RequestType {
        InitializeMatch,
        FetchScores,
        Settlement
    }

    // Structs
    struct Player {
        uint256 id;
        PlayerRole role;
        TeamSide team;
        uint8 credits;
        int256 score;
    }
    
    struct MatchData {
        string cricketApiMatchId;
        uint256 startTime;
        MatchStatus status;
        uint256[] playerIds;
        mapping(uint256 => Player) players;
        mapping(uint256 => uint256) playerIndex;
        bool fantasyEnabled;
        bool initialized;
        bool scoresFinalized;
        uint256 lastUpdated;
    }
    
    struct ChainlinkRequest {
        RequestType requestType;
        string matchId;
        uint256 contestId;
    }

    // State
    address public admin;
    address public chain11;

    // Match ID => Match data (shared across contests)
    mapping(string => MatchData) public matches;

    mapping(bytes32 => ChainlinkRequest) public pendingRequests;

    // Events
    event MatchInitializationRequested(
        string indexed matchId,
        bytes32 indexed requestId
    );
    
    event MatchInitialized(
        string indexed matchId,
        string teamAName,
        string teamBName
    );

    event MatchScoresFinalized(
        string indexed matchId,
        uint256 playerCount,
        uint256 timestamp
    );

    event ScoreFetchRequested(
        string indexed matchId,
        bytes32 indexed requestId
    );

    event SettlementRequested(
        uint256 indexed contestId,
        string indexed matchId,
        bytes32 indexed requestId
    );

    event ChainlinkRequestFailed(bytes32 indexed requestId, bytes error);

    event ScriptHashUpdated(string);

    // error
    error Unauthorized();
    error MatchNotInitialized();
    error MatchNotCompleted();
    error ScoresAlreadyFinalized();
    error InvalidPlayer();
    error ZeroAddress();

    // modifiers
    modifier onlyAdmin() {
        require(msg.sender == admin, Unauthorized());
        _;
    }

    modifier onlyChain11() {
        require(chain11 != address(0), ZeroAddress());
        require(msg.sender == chain11, Unauthorized());
        _;
    }

    modifier matchFinalized(string calldata matchId) {
        require(matches[matchId].scoresFinalized, MatchNotCompleted());
        _;
    }

    constructor(
        address _functionsRouter,
        bytes32 _donId,
        uint64 _subscriptionId
    ) FunctionsClient(_functionsRouter) {
        admin = msg.sender;
        donId = _donId;
        subscriptionId = _subscriptionId;
    }

    function initializeMatch(string calldata cricketApiMatchId) external onlyChain11 returns (string memory matchId) {
        matchId = string(abi.encodePacked(cricketApiMatchId));

        if (matches[matchId].initialized) return matchId;

        MatchData storage matchData = matches[matchId];
        matchData.cricketApiMatchId = cricketApiMatchId;

        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(_getMatchInitScript());

        string[] memory args = new string[](1);
        args[0] = cricketApiMatchId;
        req.setArgs(args);

        bytes32 requestId = _sendRequest(req.encodeCBOR(), subscriptionId, GAS_LIMIT, donId);

        pendingRequests[requestId] = ChainlinkRequest({
            requestType: RequestType.InitializeMatch,
            matchId: matchId,
            contestId: 0
        });

        emit MatchInitializationRequested(matchId, requestId);

        return matchId;
    }
    
    function requestScores(string calldata matchId) external onlyChain11 returns (bytes32 requestId) {
        MatchData storage matchData = matches[matchId];

        require(matchData.initialized, MatchNotInitialized());
        require(!matchData.scoresFinalized, ScoresAlreadyFinalized());

        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(_getScoreFetchScript());

        requestId = _sendRequest(req.encodeCBOR(), subscriptionId, GAS_LIMIT, donId);

        pendingRequests[requestId] = ChainlinkRequest({
            requestType: RequestType.InitializeMatch,
            matchId: matchId,
            contestId: 0
        });

        emit ScoreFetchRequested(matchId, requestId);
        
        return requestId;
    }
    
    function requestSettlement(
        uint256 contestId,
        string calldata matchId
    ) external onlyChain11 matchFinalized(matchId) returns (bytes32 requestId){
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(_getSettlementScript());
        string[] memory args = new string[](4);
        args[0] = contestId.toString();
        args[1] = matchId;
        args[2] = chain11.toHexString();
        args[3] = address(this).toHexString();

        req.setArgs(args);
        requestId = _sendRequest(req.encodeCBOR(), subscriptionId, GAS_LIMIT, donId);

        pendingRequests[requestId] = ChainlinkRequest({
            requestType: RequestType.Settlement,
            matchId: matchId,
            contestId: contestId
        });

        emit SettlementRequested(contestId, matchId, requestId);
        
        return requestId;
    }
    
    // View
    function isMatchInitialized(string calldata matchId) external view returns (bool) {
        return matches[matchId].initialized;
    }

    function isMatchUpcoming(string calldata matchId) external view returns (bool) {
        return matches[matchId].initialized && matches[matchId].status == MatchStatus.Upcoming;
    }
    
    function isMatchCompleted(string calldata matchId) external view returns (bool) {
        return matches[matchId].scoresFinalized && matches[matchId].status == MatchStatus.Completed;
    }
    
    function getPlayer(string calldata matchId, uint256 playerId) external view returns (
            uint256 id,
            PlayerRole role,
            TeamSide team,
            uint8 credits,
            int256 score
    ) {
        Player storage player = matches[matchId].players[playerId];
        return (
            player.id,
            player.role,
            player.team,
            player.credits,
            player.score
        );
    }

    function getPlayers(string calldata matchId, uint256[] calldata playerIds)
        external
        view
        returns (
            uint256[] memory ids,
            uint8[] memory roles,
            uint8[] memory teams,
            uint8[] memory credits
        )
    {
        uint256 length = playerIds.length;
        ids = new uint256[](length);
        roles = new uint8[](length);
        teams = new uint8[](length);
        credits = new uint8[](length);
        
        for (uint256 i = 0; i < length;) {
            Player storage player = matches[matchId].players[playerIds[i]];
            ids[i] = player.id;
            roles[i] = uint8(player.role);
            teams[i] = uint8(player.team);
            credits[i] = player.credits;
            
            unchecked { i++; }
        }
    }
    
    function getPlayerScore(string calldata matchId, uint256 playerId) external view returns (int256) {
        return matches[matchId].players[playerId].score;
    }

    function getPlayerScores(string calldata matchId, uint256[] calldata playerIds)
        external
        view
        returns (int256[] memory scores)
    {
        scores = new int256[](playerIds.length);
        for (uint256 i = 0; i < playerIds.length;) {
            scores[i] = matches[matchId].players[playerIds[i]].score;
            unchecked { i++; }
        }
    }
    
    function getMatchStatus(string calldata matchId) external view returns (MatchStatus) {
        return matches[matchId].status; 
    }

    // admin
    function setChain11(address _chain11) external onlyAdmin {
        require(_chain11 != address(0), "Zero address");
        chain11 = _chain11;
    }

    // internal
    function fulfillRequest(bytes32 requestId, bytes memory response, bytes memory err) internal override virtual {
        ChainlinkRequest memory request = pendingRequests[requestId];
        
        if (err.length > 0) {
            emit ChainlinkRequestFailed(requestId, err);
            delete pendingRequests[requestId];
            return;
        }
        
        if (request.requestType == RequestType.InitializeMatch) {
            _handleMatchInitialization(request.matchId, response);
        } else if (request.requestType == RequestType.FetchScores) {
            _handleScoreFetch(request.matchId, response);
        } else if (request.requestType == RequestType.Settlement) {
            _handleSettlement(request.contestId, response);
        }
        
        delete pendingRequests[requestId];
    }

    function _handleMatchInitialization(
        string memory matchId,
        bytes memory response
    ) internal {
        // Decode response
        (
            bool fantasyEnabled,
            bool matchStarted,
            uint256 startTime,
            uint256[] memory playerIds,
            uint8[] memory playerRoles,
            uint8[] memory playerTeams,
            uint8[] memory playerCredits
        ) = abi.decode(
            response,
            (bool, bool, uint256, uint256[], uint8[], uint8[], uint8[])
        );
        
        require(fantasyEnabled, "Fantasy not enabled");
        require(!matchStarted, "Match already started");
        
        MatchData storage matchData = matches[matchId];
        
        // Store basic metadata (no names)
        matchData.startTime = startTime;
        matchData.status = MatchStatus.Upcoming;
        matchData.fantasyEnabled = true;
        matchData.initialized = true;
        matchData.lastUpdated = block.timestamp;
        
        // Store players
        for (uint256 i = 0; i < playerIds.length; i++) {
            matchData.playerIds.push(playerIds[i]);
            matchData.players[playerIds[i]] = Player({
                id: playerIds[i],
                role: PlayerRole(playerRoles[i]),
                team: TeamSide(playerTeams[i]),
                credits: playerCredits[i],
                score: 0
            });
            matchData.playerIndex[playerIds[i]] = i;
        }
        
        emit MatchInitialized(matchId, "", "");
    }

    function _handleScoreFetch(
        string memory matchId,
        bytes memory response
    ) internal {
        // Decode scores
        (uint256[] memory playerIds, int256[] memory scores) = 
            abi.decode(response, (uint256[], int256[]));
        
        MatchData storage matchData = matches[matchId];
        
        require(playerIds.length == matchData.playerIds.length, "Length mismatch");
        
        // Update scores
        for (uint256 i = 0; i < playerIds.length;) {
            uint256 playerId = playerIds[i];
            if (matchData.players[playerId].id == 0) revert InvalidPlayer();
            
            matchData.players[playerId].score = scores[i];
            
            unchecked { i++; }
        }
        
        matchData.status = MatchStatus.Completed;
        matchData.scoresFinalized = true;
        matchData.lastUpdated = block.timestamp;
        
        emit MatchScoresFinalized(matchId, playerIds.length, block.timestamp);
    }


    function _handleSettlement(
        uint256 contestId,
        bytes memory response
    ) internal {
        // Decode winners
        (address[] memory winners, int256[] memory scores) = 
            abi.decode(response, (address[], int256[]));
        
        require(winners.length >= 3 && winners.length <= 10, "Invalid winner count");
        require(winners.length == scores.length, "Length mismatch");
        
        // Callback to Core contract
        (bool success, ) = chain11.call(
            abi.encodeWithSignature(
                "finalizeSettlement(uint256,address[],int256[])",
                contestId,
                winners,
                scores
            )
        );
        
        require(success, "Core callback failed");
    }

   function _getMatchInitScript() internal pure returns (string memory) {
        return "const t=args[0],a=await Functions.makeHttpRequest({url:`https://api.cricketdata.org/fantasy-cricket/${t}`});if(a.error)throw Error(\"API failed\");const e=a.data,r=!0===e.fantasy_enabled,o=new Date(e.start_time)<new Date,i=Math.floor(new Date(e.start_time).getTime()/1e3),s=[];e.squads.forEach((t,a)=>{t.players.forEach(t=>{s.push({id:t.player_id,role:\"batsman\"===t.role?0:\"bowler\"===t.role?1:\"allrounder\"===t.role?2:3,team:a,credits:Math.min(Math.max(Math.floor(t.fantasy_credit),50),100)})})});const n=s.map(t=>t.id),l=s.map(t=>t.role),d=s.map(t=>t.team),u=s.map(t=>t.credits),c=ethers.utils.defaultAbiCoder.encode([\"bool\",\"bool\",\"uint256\",\"uint256[]\",\"uint8[]\",\"uint8[]\",\"uint8[]\"],[r,o,i,n,l,d,u]);return ethers.utils.arrayify(c);";
    }
    
    /**
     * @notice Compressed JavaScript for score fetching
     */
    function _getScoreFetchScript() internal pure returns (string memory) {
        return "const t=args[0],r=await Functions.makeHttpRequest({url:`https://api.cricketdata.org/fantasy-cricket/${t}/points`});if(r.error)throw Error(\"API failed\");const a=r.data;if(\"completed\"!==a.status)throw Error(\"Match not completed\");const o=a.player_points;if(!o||0===o.length)throw Error(\"No points\");o.sort((t,r)=>t.player_id-r.player_id);const e=o.map(t=>t.player_id),i=o.map(t=>Math.floor(t.fantasy_points)),s=ethers.utils.defaultAbiCoder.encode([\"uint256[]\",\"int256[]\"],[e,i]);return ethers.utils.arrayify(s);";
    }
    

    function _getSettlementScript() internal pure returns (string memory) {
        return "const t=parseInt(args[0]),e=args[1],r=args[2],s=args[3],n=new ethers.providers.JsonRpcProvider(\"https://mainnet.base.org\"),a=new ethers.Contract(r,[\"function getParticipants(uint256) view returns (address[])\",\"function getTeamData(uint256,address) view returns (uint256[],uint256,uint256)\"],n),i=new ethers.Contract(s,[\"function getPlayerIds(string) view returns (uint256[])\",\"function getPlayerScores(string,uint256[]) view returns (int256[])\"],n),o=await a.getParticipants(t);if(!o||0===o.length)throw Error(\"No participants\");const c=await i.getPlayerIds(e),g=await i.getPlayerScores(e,c),u=new Map;for(let t=0;t<c.length;t++)u.set(c[t].toString(),parseInt(g[t].toString()));const l=o.map(e=>a.getTeamData(t,e)),d=await Promise.all(l),p=[];for(let t=0;t<o.length;t++){const e=o[t],r=d[t],s=r[0],n=r[1],a=r[2];let i=0;for(const t of s){const e=u.get(t.toString())||0;t.eq(n)?i+=2*e:t.eq(a)?i+=Math.floor(1.5*e):i+=e}p.push({address:e,score:i})}p.sort((t,e)=>e.score-t.score);const h=o.length>=10?10:3,w=p.slice(0,h),f=w.map(t=>t.address),P=w.map(t=>t.score),m=ethers.utils.defaultAbiCoder.encode([\"address[]\",\"int256[]\"],[f,P]);return ethers.utils.arrayify(m);";
    }
}