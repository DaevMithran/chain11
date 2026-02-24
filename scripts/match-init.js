// args[0] is the cricketApiMatchId passed from the request
const matchId = args[0];

// 1. Fetch data from the Cricket Data API
const r = await Functions.makeHttpRequest({
  url: `https://api.cricketdata.org/fantasy-cricket/${matchId}`
});

if (r.error) {
  throw Error('API failed');
}

const d = r.data;

// 2. Process Metadata
const enabled = d.fantasy_enabled === true;
// Check if start time is in the past
const started = new Date(d.start_time) < new Date();
// Convert ISO string to Unix timestamp (seconds)
const startTime = Math.floor(new Date(d.start_time).getTime() / 1000);

// 3. Process Squads & Players
const players = [];

// d.squads is an array of teams. ti is the team index (0 or 1)
d.squads.forEach((sq, ti) => {
  sq.players.forEach(p => {
    players.push({
      id: p.player_id,
      // Map string roles to enums: Batsman(0), Bowler(1), AllRounder(2), WicketKeeper(3)
      role: p.role === 'batsman' ? 0 : 
            p.role === 'bowler' ? 1 : 
            p.role === 'allrounder' ? 2 : 3,
      team: ti,
      // Clamp credits between 50 and 100
      credits: Math.min(Math.max(Math.floor(p.fantasy_credit), 50), 100)
    });
  });
});

// 4. Extract arrays for encoding
const pIds = players.map(p => p.id);
const roles = players.map(p => p.role);
const teams = players.map(p => p.team);
const credits = players.map(p => p.credits);

// 5. ABI Encode the result
// Matches Solidity: (bool, bool, uint256, uint256[], uint8[], uint8[], uint8[])
const ac = ethers.utils.defaultAbiCoder;
const enc = ac.encode(
  ['bool', 'bool', 'uint256', 'uint256[]', 'uint8[]', 'uint8[]', 'uint8[]'],
  [enabled, started, startTime, pIds, roles, teams, credits]
);

// Return bytes
return ethers.utils.arrayify(enc);