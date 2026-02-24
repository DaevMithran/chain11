import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { network } from "hardhat";
import { keccak256, parseEther, toBytes, zeroAddress, encodeAbiParameters, parseAbiParameters, GetContractReturnType, Abi, PublicClient, WalletClient } from "viem";

type GenericContract = GetContractReturnType<Abi, PublicClient>;

describe("Chain11", async function () {
  const { viem } = await network.connect();
  const publicClient = await viem.getPublicClient();
  const [owner, user1, user2, user3] = await viem.getWalletClients();

  async function deployPlatform() {
    const mockRouter = await viem.deployContract("Chain11Mock");

    const chain11Oracle = await viem.deployContract("Chain11Oracle", [
      mockRouter.address,
      "0x66756e2d626173652d6d61696e6e65742d310000000000000000000000000000",
      1n
    ])

    const chain11 = await viem.deployContract("Chain11", [ chain11Oracle.address ]);

    await chain11Oracle.write.setChain11([chain11.address]);

    return { chain11, chain11Oracle, mockRouter }
  }

async function initializeMatch(chain11Oracle: any, mockRouter: any, matchId: string) {
    // Get request event
    const events = await publicClient.getContractEvents({
      address: chain11Oracle.address,
      abi: chain11Oracle.abi,
      eventName: "MatchInitializationRequested",
    });
    const requestId = events[events.length - 1].args.requestId;
    // Create 44 players (22 per team) with valid roles
    const playerIds = Array.from({ length: 44 }, (_, i) => BigInt(1000 + i));
    
    // Ensure we have valid role distribution for team building
    // Team A (0-21): 6 batsmen, 6 bowlers, 2 all-rounders, 2 wicket-keepers, 6 batsmen
    // Team B (22-43): same
    const roles = [
      // Team A
      0, 0, 0, 0, 0, 0, // 6 batsmen
      1, 1, 1, 1, 1, 1, // 6 bowlers
      2, 2, 2, 2,       // 4 all-rounders
      3, 3, 3, 3,       // 4 wicket-keepers
      0, 0,             // 2 more batsmen
      // Team B (same pattern)
      0, 0, 0, 0, 0, 0, // 6 batsmen
      1, 1, 1, 1, 1, 1, // 6 bowlers
      2, 2, 2, 2,       // 4 all-rounders
      3, 3, 3, 3,       // 4 wicket-keepers
      0, 0,             // 2 more batsmen
    ];
    
    const teams = Array.from({ length: 44 }, (_, i) => i < 22 ? 0 : 1);
    const credits = Array.from({ length: 44 }, () => 80);
    
    // Encode match initialization response
    const encodedResponse = encodeAbiParameters(
      parseAbiParameters('bool,bool,uint256,uint256[],uint8[],uint8[],uint8[]'),
      [
        true,  // fantasy enabled
        false, // not started
        BigInt(Math.floor(Date.now() / 1000)) + 7200n, // start time
        playerIds,
        roles,
        teams,
        credits,
      ]
    );
    
    // Fulfill request
    const hash = await mockRouter.write.fulfillRequest([
      chain11Oracle.address,
      requestId,
      encodedResponse,
      "0x",
    ]);
    
    await publicClient.waitForTransactionReceipt({ hash });
    return playerIds;
  }

  describe("Deployment", function() {
    it("Should deploy chain11Oracle", async function() {
      const { chain11Oracle } = await deployPlatform();

      const admin = await chain11Oracle.read.admin();
      const subscriptionId = await chain11Oracle.read.subscriptionId();

      assert.notEqual(admin, zeroAddress);
      assert.equal(subscriptionId, 1n);
    })

    it("Should link contracts bidirectionally", async function() {
      const { chain11, chain11Oracle } = await deployPlatform();

      const chain11OracleAddress = await chain11.read.chain11Oracle();
      const chain11Adress = await chain11Oracle.read.chain11();

      assert.equal(chain11Oracle.address.toLowerCase(), chain11OracleAddress.toLowerCase());
      assert.equal(chain11.address.toLowerCase(), chain11Adress.toLowerCase());
    })
  })


  describe("Contest Creation", function() {
    it("Should create contest and trigger match initialization", async function() {
      const { chain11, chain11Oracle } = await deployPlatform();

      const matchId = "match_ind_vs_aus_001";
      const blockNumber = await publicClient.getBlockNumber();
      const deadline = BigInt(Math.floor(Date.now()/1000)) + 3600n;
      const maxParticipants = 100n;
      const fee = parseEther("0.01");

      const hash = await chain11.write.createContest(
        [matchId, deadline, maxParticipants],
        { value: fee }
      );

      await publicClient.waitForTransactionReceipt({ hash })

      // Validate ContestCreated event
      const contestEvents = await publicClient.getContractEvents({
        address: chain11.address,
        abi: chain11.abi,
        eventName: "ContestCreated",
        fromBlock: blockNumber,
        strict: true
      })

      assert.equal(contestEvents.length, 1);
      assert.equal(contestEvents[0].args.contestId, 0n);

      // Validate MatchInitialization event
      const matchEvents = await publicClient.getContractEvents({
        address: chain11Oracle.address,
        abi: chain11Oracle.abi,
        eventName: "MatchInitializationRequested",
        fromBlock: blockNumber,
      })

      assert.equal(matchEvents.length, 1);
      assert.equal(matchEvents[0].args.matchId?.toString(), keccak256(toBytes(matchId)));

      const [storedMatchId, creator, prizePool, participantCount, maxPart] = await chain11.read.getContest([0n]);

      assert.equal(storedMatchId, matchId);
      assert.equal(prizePool, parseEther("0.009"));
      assert.equal(participantCount, 0n);
      assert.equal(maxPart, 100n);
    })
  })

  describe("Match Initialization", function() {
    it("Should initialize match after Chainlink callback", async function() {
      const { chain11, chain11Oracle, mockRouter } = await deployPlatform();

      const matchId = "match_ind_vs_aus_001";
      const deadline = BigInt(Math.floor(Date.now() / 1000)) + 3600n;

      const hash = await chain11.write.createContest(
        [matchId, deadline, 100n],
        { value: parseEther("0.01") }
      );
      
      await publicClient.waitForTransactionReceipt({ hash });
      
      // Initialize match
      const playerIds = await initializeMatch(chain11Oracle, mockRouter, matchId);
      
      // Check if initialized
      const isInitialized = await chain11Oracle.read.isMatchInitialized([matchId]);
      assert.equal(isInitialized, true);

      const [id, role, team, credits, score] = await chain11Oracle.read.getPlayer([matchId, playerIds[0]]);
      assert.equal(team, 0);
      assert.equal(role, 0);
      assert.equal(credits, 80);
      assert.equal(score, 0n);
      assert.equal(id, playerIds[0]);
    })
  });

});
