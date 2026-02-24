const apiMatchId = args[0];

// 1. Fetch Points Data
const r = await Functions.makeHttpRequest({
  url: `https://api.cricketdata.org/fantasy-cricket/${apiMatchId}/points`
});

if (r.error) {
  throw Error('API failed');
}

const d = r.data;

// 2. Validate Match Status
if (d.status !== 'completed') {
  throw Error('Match not completed');
}

const pts = d.player_points;
if (!pts || pts.length === 0) {
  throw Error('No points');
}

// 3. Sort by Player ID (Critical for deterministic ordering)
pts.sort((a, b) => a.player_id - b.player_id);

// 4. Extract Data
const pIds = pts.map(p => p.player_id);
const scores = pts.map(p => Math.floor(p.fantasy_points));

// 5. ABI Encode
// Matches Solidity: (uint256[], int256[])
const ac = ethers.utils.defaultAbiCoder;
const enc = ac.encode(
  ['uint256[]', 'int256[]'], 
  [pIds, scores]
);

return ethers.utils.arrayify(enc);