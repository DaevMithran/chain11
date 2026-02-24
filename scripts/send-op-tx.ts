import { network } from "hardhat";

const { viem } = await network.connect({
  network: "hardhatOp",
  chainType: "op",
});

console.log("Sending transaction using the OP chain type");

const publicClient = await viem.getPublicClient();
const [senderClient] = await viem.getWalletClients();

console.log("Sending 1 wei from", senderClient.account.address, "to itself");

const l1Gas = await publicClient.estimateL1Gas({
  account: senderClient.account.address,
  to: senderClient.account.address,
  value: 1n,
});

console.log("Estimated L1 gas:", l1Gas);

console.log("Sending L2 transaction");
const tx = await senderClient.sendTransaction({
  to: senderClient.account.address,
  value: 1n,
});

await publicClient.waitForTransactionReceipt({ hash: tx });

console.log("Transaction sent successfully");


    // function settleContest(uint256 contestId) external {
    //     Contest storage contest = contests[contestId];
    //     if (contest.state != ContestState.Locked) revert ContestNotLocked();
        
    //     string memory matchId = contest.matchId;
    //     MatchData storage matchData = matches[matchId];
    //     if (!matchData.scoresFinalized) revert ScoresNotFinalized();
    //     if (matchData.status != MatchStatus.Completed) revert MatchNotCompleted();
        
    //     uint256 participantCount = contest.participants.length;
    //     if (participantCount < 3) revert InsufficientParticipants();
        
    //     // Determine prize structure
    //     bool useTopTen = participantCount >= 10;
    //     uint256 K = useTopTen ? 10 : 3;
                
    //     TopKEntry[] memory topK = new TopKEntry[](K);
    //     uint256 topKSize = 0;
        
    //     // Find top K winners
    //     for (uint256 i = 0; i < participantCount; i++) {
    //         address user = contest.participants[i];
    //         int256 score = _calculateTeamScore(contest, matchData, user);
    //         contest.teams[user].finalScore = score;
            
    //         if (topKSize < K) {
    //             // Not full yet, add directly
    //             topK[topKSize] = TopKEntry(user, score);
    //             topKSize++;
    //         } else {
    //             // Find minimum in top-K
    //             uint256 minIdx = 0;
    //             for (uint256 j = 1; j < K; j++) {
    //                 if (topK[j].score < topK[minIdx].score) {
    //                     minIdx = j;
    //                 }
    //             }
                
    //             // Replace if better
    //             if (score > topK[minIdx].score) {
    //                 topK[minIdx] = TopKEntry(user, score);
    //             }
    //         }
    //     }
        
    //     // Sort top-K (insertion sort, K is small)
    //     for (uint256 i = 1; i < topKSize; i++) {
    //         TopKEntry memory key = topK[i];
    //         int256 j = int256(i) - 1;
            
    //         while (j >= 0 && topK[uint256(j)].score < key.score) {
    //             topK[uint256(j + 1)] = topK[uint256(j)];
    //             j--;
    //         }
    //         topK[uint256(j + 1)] = key;
    //     }
        
    //     // Distribute prizes
    //     uint256 pool = contest.prizePool;
    //     for (uint256 i = 0; i < topKSize; i++) {
    //         uint256 prize = _getPrizeForRank(i, pool, useTopTen);
    //         contest.claimableWinnings[topK[i].user] = prize;
    //         contest.winners.push(topK[i].user);
    //     }
        
    //     contest.state = ContestState.Settled;
        
    //     emit ContestSettled(contestId, contest.winners, pool, block.timestamp);
    // }