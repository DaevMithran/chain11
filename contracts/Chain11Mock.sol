// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title Chain11Mock
 * @notice Mock Chainlink Functions Router for testing
 * @dev Simulates Chainlink Functions callback mechanism
 */
contract Chain11Mock {
    
    event RequestSent(bytes32 indexed requestId);
    event RequestFulfilled(bytes32 indexed requestId);
    
    /**
     * @notice Mock sending a request (does nothing, just emits event)
     */
    function sendRequest(
        uint64,
        bytes calldata,
        uint16,
        uint32,
        bytes32
    ) external returns (bytes32 requestId) {
        requestId = keccak256(abi.encodePacked(block.timestamp, msg.sender));
        emit RequestSent(requestId);
        return requestId;
    }
    
    /**
     * @notice Fulfill a request by calling back to consumer
     * @dev In real Chainlink, this is called by oracle nodes
     * @param consumer Address of the consumer contract
     * @param requestId Request ID to fulfill
     * @param response Encoded response data
     * @param err Error data (empty if success)
     */
    function fulfillRequest(
        address consumer,
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) external {
        // Call the consumer's handleOracleFulfillment
        // 1. Perform the call
            (bool success, bytes memory returnData) = consumer.call(
                abi.encodeWithSignature(
                    "handleOracleFulfillment(bytes32,bytes,bytes)",
                    requestId,
                    response,
                    err
                )
            );

            // 2. STOP if it failed and show me why!
            if (!success) {
                // If returnData is empty, it's a panic (index out of bounds, etc)
                if (returnData.length == 0) revert("Inner call failed (Panic)");
                // Otherwise, bubble up the error string
                assembly {
                    revert(add(returnData, 32), mload(returnData))
                }
            }
        
        emit RequestFulfilled(requestId);
    }
}
