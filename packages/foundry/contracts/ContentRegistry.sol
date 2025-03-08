// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title ContentRegistry
 * @dev Manages content registration and references on-chain
 */
contract ContentRegistry is Ownable, ReentrancyGuard {

    address public moderationContract;

    enum ContentStatus {
        Active,
        UnderReview,
        Removed,
        Approved
    }

    struct Content {
        address creator;
        string contentHash;
        uint256 timestamp;
        ContentStatus status;
        bool exists;
    }

    bytes32[] public contentIds;
    mapping(bytes32 => Content) public contents;
    mapping(address => bytes32[]) public userContents;

    // Events
    event ContentCreated(bytes32 indexed contentId, address indexed creator, string contentHash);
    event ContentStatusChanged(bytes32 indexed contentId, ContentStatus previousStatus, ContentStatus newStatus);
    event ContentUpdated(bytes32 indexed contentId, string newContentHash);

    constructor() Ownable(msg.sender) {}

    /**
     * @dev Creates new content entry
     * @param _contentHash IPFS hash of the content
     * @return contentId The unique identifier for the content
     */
    function createContent(string calldata _contentHash) 
        external 
        nonReentrant 
        returns (bytes32 contentId) 
    {
        contentId = keccak256(abi.encodePacked(_contentHash, msg.sender, block.timestamp));
        
        require(!contents[contentId].exists, "Content already exists");
        
        contents[contentId] = Content({
            creator: msg.sender,
            contentHash: _contentHash,
            timestamp: block.timestamp,
            status: ContentStatus.Active,
            exists: true
        });
        
        userContents[msg.sender].push(contentId);
        contentIds.push(contentId);
        emit ContentCreated(contentId, msg.sender, _contentHash);
        
        return contentId;
    }

    /**
    * @dev Updates content hash
    * @param _contentId The unique content identifier
    * @param _newContentHash The new content hash
     */
    function updateContentHash(bytes32 _contentId, string calldata _newContentHash)
        external
        nonReentrant
    {
        require(contents[_contentId].exists, "Content doesn't exist");
        require(msg.sender == contents[_contentId].creator, "Not authorized");
        require(contents[_contentId].status != ContentStatus.Approved, "Content is under review or have been removed");

        contents[_contentId].contentHash = _newContentHash;

        emit ContentUpdated(_contentId, _newContentHash);
    }

    /**
     * @dev Updates content status
     * @param _contentId The unique content identifier
     * @param _newStatus The new status to set
     */
    function updateContentStatus(bytes32 _contentId, ContentStatus _newStatus) 
        external 
        nonReentrant
    {
        require(contents[_contentId].exists, "Content doesn't exist");
        
        require(msg.sender == owner() || msg.sender == address(moderationContract), "Not authorized");
        
        ContentStatus previousStatus = contents[_contentId].status;
        contents[_contentId].status = _newStatus;
        
        emit ContentStatusChanged(_contentId, previousStatus, _newStatus);
    }
    
    /**
     * @dev Gets paginated content with optional status filter
     * @param _offset Starting index for pagination
     * @param _limit Maximum number of items to return
     * @param _status Optional status filter (-1 for all statuses)
     * @return contents_ Array of content structs
     * @return total Total number of content items matching criteria
     */
    function getPaginatedContent(
        uint256 _offset,
        uint256 _limit,
        int8 _status
    ) external view returns (
        Content[] memory contents_,
        uint256 total
    ) {
        Content[] memory allContents = new Content[](_offset + _limit);
        uint256 count = 0;
        total = 0;

        for (uint256 i = 0; i < contentIds.length; i++) {
            bytes32 contentId = contentIds[i];
            Content storage content = contents[contentId];
            
            if (_status >= 0) {
                if (content.status != ContentStatus(uint8(_status))) {
                    continue;
                }
            }
            total++;
            
            if (total <= _offset) {
                continue;
            }
            
            if (count < _limit) {
                allContents[count] = content;
                count++;
            }
        }

        contents_ = new Content[](count);
        for (uint256 i = 0; i < count; i++) {
            contents_[i] = allContents[i];
        }

        return (contents_, total);
    }

    /**
     * @dev Gets all content for a user
     * @param _user The user address
     * @return Content array containing all content created by the user
     */
    function getUserContent(address _user)
        external
        view
        returns (Content[] memory)
    {
        bytes32[] memory userContentIds = userContents[_user];
        Content[] memory userContent = new Content[](userContentIds.length);
        
        for (uint256 i = 0; i < userContentIds.length; i++) {
            userContent[i] = contents[userContentIds[i]];
        }
        
        return userContent;
    }

    /**
     * @dev Sets the moderation contract address
     * @param _moderationContract Address of the moderation contract
     */
    function setModerationContract(address _moderationContract) external onlyOwner {
        moderationContract = _moderationContract;
    }
}