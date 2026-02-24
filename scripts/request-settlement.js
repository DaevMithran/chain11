// 1. Parse Arguments
const contestId = parseInt(args[0]);
const matchId = args[1];
const coreAddr = args[2];
const oracleAddr = args[3];

// 2. Define Minimal ABIs for Read Calls
const coreAbi = [
  'function getParticipants(uint256) view returns (address[])',
  'function getTeamData(uint256,address) view returns (uint256[],uint256,uint256)'
];
const oracleAbi = [
  'function getPlayerIds(string) view returns (uint256[])',
  'function getPlayerScores(string,uint256[]) view returns (int256[])'
];

// 3. Setup Provider (Base Mainnet) & Contracts
const provider = new ethers.providers.JsonRpcProvider('https://mainnet.base.org');
const core = new ethers.Contract(coreAddr, coreAbi, provider);
const oracle = new ethers.Contract(oracleAddr, oracleAbi, provider);

// 4. Fetch Participants
const participants = await core.getParticipants(contestId);
if (!participants || participants.length === 0) {
  throw Error('No participants');
}

// 5. Fetch Match Data (Optimized: Single RPC call for all scores)
const allPlayerIds = await oracle.getPlayerIds(matchId);
const allPlayerScores = await oracle.getPlayerScores(matchId, allPlayerIds);

// Build efficient lookup map: PlayerID (string) -> Score (int)
const scoreMap = new Map();
for (let i = 0; i < allPlayerIds.length; i++) {
  scoreMap.set(
    allPlayerIds[i].toString(), 
    parseInt(allPlayerScores[i].toString())
  );
}

// 6. Fetch Team Data for All Participants (Parallelized)
const teamDataPromises = participants.map(user => 
  core.getTeamData(contestId, user)
);
const allTeamData = await Promise.all(teamDataPromises);

// 7. Calculate Scores Off-Chain
const teamScores = [];

for (let i = 0; i < participants.length; i++) {
  const user = participants[i];
  const teamData = allTeamData[i];
  
  const playerIds = teamData[0];
  const captainId = teamData[1];
  const viceCaptainId = teamData[2];
  
  let totalScore = 0;
  
  // Sum up points based on roles
  for (const playerId of playerIds) {
    const score = scoreMap.get(playerId.toString()) || 0;
    
    if (playerId.eq(captainId)) {
      totalScore += score * 2; // Captain 2x
    } else if (playerId.eq(viceCaptainId)) {
      totalScore += Math.floor(score * 1.5); // Vice-Captain 1.5x
    } else {
      totalScore += score; // Normal 1x
    }
  }
  
  teamScores.push({ address: user, score: totalScore });
}

// 8. Determine Winners (Sort Descending)
teamScores.sort((a, b) => b.score - a.score);

// Pick Top K (Top 10 if large contest, else Top 3)
const K = participants.length >= 10 ? 10 : 3;
const topK = teamScores.slice(0, K);

// 9. Prepare Response
const winners = topK.map(t => t.address);
const scores = topK.map(t => t.score);

// 10. ABI Encode
// Matches Solidity: (address[], int256[])
const ac = ethers.utils.defaultAbiCoder;
const enc = ac.encode(
  ['address[]', 'int256[]'], 
  [winners, scores]
);

return ethers.utils.arrayify(enc);