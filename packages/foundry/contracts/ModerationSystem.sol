// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./ContentRegistry.sol";
import "./ModeratorRegistry.sol";

/**
 * @title ModerationSystem
 * @dev Manages content moderation using Byzantine fault tolerance principles
 */
contract ModerationSystem is Ownable, ReentrancyGuard {

    ContentRegistry public contentRegistry;
    ModeratorRegistry public moderatorRegistry;
    
    struct ModerationRequest {
        bytes32 contentId;
        uint256 timestamp;
        uint256 requiredModerators;
        uint256 moderationsCount;
        bool resolved;
        bool exists;
    }

    struct ModeratorRequestView {
        bytes32 requestId;
        bytes32 contentId;
        uint256 timestamp;
        uint256 requiredModerators;
        uint256 moderationsCount;
        bool resolved;
        bool exists;
        bool hasVoted;
    }

    bytes32[] public requestIds;
    
    mapping(bytes32 => ModerationRequest) public moderationRequests;
    mapping(bytes32 => address[]) public selectedModerators;
    mapping(bytes32 => mapping(address => bool)) public hasVoted;
    mapping(bytes32 => mapping(uint8 => uint256)) public votes;
    
    // Constants for BFT
    uint256 public BFT_TOLERANCE = 2;
    
    // Events
    event ModerationRequested(bytes32 indexed requestId, bytes32 indexed contentId);
    event ModeratorSelected(bytes32 indexed requestId, address indexed moderator);
    event ModerationVoteCast(bytes32 indexed requestId, address indexed moderator, uint8 vote);
    event ModerationResolved(bytes32 indexed requestId, uint8 decision);
    
    /**
     * @dev Constructor to set registry contracts
     * @param _contentRegistry Address of content registry contract
     * @param _moderatorRegistry Address of moderator registry contract
     */
    constructor(ContentRegistry _contentRegistry, ModeratorRegistry _moderatorRegistry) Ownable(msg.sender) {
        contentRegistry = _contentRegistry;
        moderatorRegistry = _moderatorRegistry;
    }
    
    /**
     * @dev Request moderation for content
     * @param _contentId ID of content to moderate
     */
    function requestModeration(bytes32 _contentId) external nonReentrant {
        bytes32 requestId = keccak256(abi.encodePacked(_contentId, block.timestamp));
        require(!moderationRequests[requestId].exists, "Request already exists");
        
        (address creator, , , , bool exists) = contentRegistry.contents(_contentId);
        require(exists, "Content does not exist");
        require(msg.sender == creator, "Only content creator can request moderation");
        
        uint256 requiredModerators = 3 * BFT_TOLERANCE + 1;
        
        require(moderatorRegistry.getActiveModeratorCount() >= requiredModerators, "Not enough active moderators");
        
        moderationRequests[requestId] = ModerationRequest({
            contentId: _contentId,
            timestamp: block.timestamp,
            requiredModerators: requiredModerators,
            moderationsCount: 0,
            resolved: false,
            exists: true
        });
        
        requestIds.push(requestId);
        contentRegistry.updateContentStatus(_contentId, ContentRegistry.ContentStatus.UnderReview);
        
        _selectModerators(requestId, requiredModerators);
        
        emit ModerationRequested(requestId, _contentId);
    }

    /**
     * @dev Cast a vote for a moderation request
     * @param _requestId The moderation request ID
     * @param _vote The vote (0 = remove, 1 = keep)
     */
    function castVote(bytes32 _requestId, uint8 _vote) external nonReentrant {
        require(moderationRequests[_requestId].exists, "Request doesn't exist");
        require(!moderationRequests[_requestId].resolved, "Request already resolved");
        
        bool isSelected = false;
        for (uint256 i = 0; i < selectedModerators[_requestId].length; i++) {
            if (selectedModerators[_requestId][i] == msg.sender) {
                isSelected = true;
                break;
            }
        }
        require(isSelected, "Not selected for this request");
        
        require(!hasVoted[_requestId][msg.sender], "Already voted");
        
        votes[_requestId][_vote]++;
        hasVoted[_requestId][msg.sender] = true;
        moderationRequests[_requestId].moderationsCount++;
        
        emit ModerationVoteCast(_requestId, msg.sender, _vote);
        
        _checkResolution(_requestId);
    }

    /**
     * @dev Get moderation requests for a specific moderator
     * @param _moderator The address of the moderator
     * @param _offset The offset for pagination
     * @param _limit The limit for pagination
     * @return requests_ The moderation requests with their IDs and voting status
     * @return total The total number of moderation requests
     */
    function getModeratorRequests(
        address _moderator,
        uint256 _offset,
        uint256 _limit
    ) external view returns (
        ModeratorRequestView[] memory requests_,
        uint256 total
    ) {
        ModeratorRequestView[] memory allRequests = new ModeratorRequestView[](_offset + _limit);
        uint256 count = 0;
        total = 0;

        for (uint256 i = 0; i < requestIds.length; i++) {
            bytes32 requestId = requestIds[i];
            ModerationRequest storage request = moderationRequests[requestId];
            
            bool isSelected = false;
            for (uint256 j = 0; j < selectedModerators[requestId].length; j++) {
                if (selectedModerators[requestId][j] == _moderator) {
                    isSelected = true;
                    break;
                }
            }
            
            if (!isSelected) {
                continue;
            }
            
            total++;
            
            if (total <= _offset) {
                continue;
            }
            
            if (count < _limit) {
                allRequests[count] = ModeratorRequestView({
                    requestId: requestId,
                    contentId: request.contentId,
                    timestamp: request.timestamp,
                    requiredModerators: request.requiredModerators,
                    moderationsCount: request.moderationsCount,
                    resolved: request.resolved,
                    exists: request.exists,
                    hasVoted: hasVoted[requestId][_moderator]
                });
                count++;
            }
        }

        requests_ = new ModeratorRequestView[](count);
        for (uint256 i = 0; i < count; i++) {
            requests_[i] = allRequests[i];
        }

        return (requests_, total);
    }

    /**
     * @dev Internal function to select moderators for a request
     * @param _requestId The moderation request ID
     * @param _count Number of moderators to select
     */
    function _selectModerators(bytes32 _requestId, uint256 _count) internal {
        uint256 offset = 0;
        uint256 limit = 100;
        uint256 selected = 0;
        
        //TODO: Implement a verifiable random function to prevent gaming the selection
        
        while (selected < _count) {
            address[] memory moderators = moderatorRegistry.getActiveModerators(offset, limit);
            
            if (moderators.length == 0) {
                break;
            }
            
            for (uint256 i = 0; i < moderators.length && selected < _count; i++) {
                address moderator = moderators[i];
                
                selectedModerators[_requestId].push(moderator);
                selected++;
                
                emit ModeratorSelected(_requestId, moderator);
            }
            
            offset += limit;
        }
    }
    
    /**
     * @dev Check if a request can be resolved
     * @param _requestId The moderation request ID
     */
    function _checkResolution(bytes32 _requestId) internal {
        ModerationRequest storage request = moderationRequests[_requestId];
        
        if (request.moderationsCount < request.requiredModerators) {
            return;
        }
        
        uint256 requiredConsensus = 2 * BFT_TOLERANCE + 1;
        
        uint8 decision;
        bool resolved = false;
        
        if (votes[_requestId][0] >= requiredConsensus) {
            decision = 0;
            resolved = true;
        }
        else if (votes[_requestId][1] >= requiredConsensus) {
            decision = 1;
            resolved = true;
        }
        
        if (resolved) {
            request.resolved = true;
            
            if (decision == 0) {
                contentRegistry.updateContentStatus(request.contentId, ContentRegistry.ContentStatus.Removed);
            } else {
                contentRegistry.updateContentStatus(request.contentId, ContentRegistry.ContentStatus.Approved);
            }
            
            _updateReputations(_requestId, decision);
            
            emit ModerationResolved(_requestId, decision);
        }
    }
    
    /**
     * @dev Update reputations of moderators based on consensus
     * @param _requestId The moderation request ID
     * @param _consensusDecision The decision that reached consensus
     */
    function _updateReputations(bytes32 _requestId, uint8 _consensusDecision) internal {
        for (uint256 i = 0; i < selectedModerators[_requestId].length; i++) {
            address moderator = selectedModerators[_requestId][i];
            
            if (hasVoted[_requestId][moderator]) {
                (uint256 reputation, , ) = moderatorRegistry.getModeratorData(moderator);
                
                uint8 moderatorVote = votes[_requestId][0] > 0 && hasVoted[_requestId][moderator] ? 0 : 1;
                
                if (moderatorVote == _consensusDecision) {
                    uint256 newReputation = reputation + 2;
                    moderatorRegistry.updateReputation(moderator, newReputation);
                } else {
                    uint256 newReputation = reputation > 5 ? reputation - 5 : 1;
                    moderatorRegistry.updateReputation(moderator, newReputation);
                }
            }
        }
    }
    
    /**
     * @dev Get information about a moderation request
     * @param _requestId The moderation request ID
     */
    function getModerationInfo(bytes32 _requestId) 
        external 
        view 
        returns (
            bytes32 contentId,
            uint256 timestamp,
            uint256 requiredModerators,
            uint256 moderationsCount,
            bool resolved,
            uint256 removeVotes,
            uint256 keepVotes
        ) 
    {
        require(moderationRequests[_requestId].exists, "Request doesn't exist");
        ModerationRequest storage request = moderationRequests[_requestId];
        
        return (
            request.contentId,
            request.timestamp,
            request.requiredModerators,
            request.moderationsCount,
            request.resolved,
            votes[_requestId][0],
            votes[_requestId][1]
        );
    }
    
    /**
     * @dev Get selected moderators for a request
     * @param _requestId The moderation request ID
     */
    function getSelectedModerators(bytes32 _requestId) 
        external 
        view 
        returns (address[] memory) 
    {
        require(moderationRequests[_requestId].exists, "Request doesn't exist");
        return selectedModerators[_requestId];
    }
    
    /**
     * @dev Set the BFT tolerance (f)
     * @param _tolerance New tolerance value
     */
    function setBFTTolerance(uint256 _tolerance) external onlyOwner {
        require(_tolerance > 0, "Tolerance must be positive");
        BFT_TOLERANCE = _tolerance;
    }
}