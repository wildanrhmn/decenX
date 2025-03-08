// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title ModeratorRegistry
 * @dev Manages moderator registration and reputation
 */
contract ModeratorRegistry is Ownable, ReentrancyGuard {
    address public moderationContract;

    struct Moderator {
        uint256 reputation;
        uint256 stake;
        bool active;
        bool exists;
    }
    
    mapping(address => Moderator) public moderators;
    address[] public activeModerators;
    uint256 public constant MINIMUM_STAKE = 0.001 ether;
    
    // Events
    event ModeratorRegistered(address indexed moderator, uint256 initialStake);
    event ModeratorStakeIncreased(address indexed moderator, uint256 additionalStake);
    event ModeratorStakeWithdrawn(address indexed moderator, uint256 amount);
    event ModeratorReputationChanged(address indexed moderator, uint256 previousReputation, uint256 newReputation);
    event ModeratorStatusChanged(address indexed moderator, bool active);
    
    constructor() Ownable(msg.sender) {}
    
    /**
     * @dev Register as a moderator
     */
    function registerAsModerator() external payable nonReentrant {
        require(!moderators[msg.sender].exists, "Already registered");
        require(msg.value >= MINIMUM_STAKE, "Stake below minimum");

        moderators[msg.sender] = Moderator({
            reputation: 100,
            stake: msg.value,
            active: true,
            exists: true
        });
        
        activeModerators.push(msg.sender);
        
        emit ModeratorRegistered(msg.sender, msg.value);
        emit ModeratorStatusChanged(msg.sender, true);
    }
    
    /**
     * @dev Increase moderator stake
     */
    function increaseStake() external payable nonReentrant {
        require(moderators[msg.sender].exists, "Not registered");
        
        moderators[msg.sender].stake += msg.value;
        
        emit ModeratorStakeIncreased(msg.sender, msg.value);
    }
    
    /**
     * @dev Withdraw part of the stake
     * @param _amount Amount to withdraw
     */
    function withdrawStake(uint256 _amount) external nonReentrant {
        require(moderators[msg.sender].exists, "Not registered");
        require(moderators[msg.sender].stake - _amount >= MINIMUM_STAKE, "Cannot withdraw below minimum stake");
        
        moderators[msg.sender].stake -= _amount;
        
        (bool success,) = payable(msg.sender).call{value: _amount}("");
        require(success, "Transfer failed");
        
        emit ModeratorStakeWithdrawn(msg.sender, _amount);
    }
    
    /**
     * @dev Update moderator reputation (only callable by moderation contract)
     * @param _moderator Moderator address
     * @param _newReputation New reputation score
     */
    function updateReputation(address _moderator, uint256 _newReputation) external {
        require(msg.sender == owner() || msg.sender == moderationContract, "Not authorized");
        require(moderators[_moderator].exists, "Moderator doesn't exist");
        
        uint256 previousReputation = moderators[_moderator].reputation;
        moderators[_moderator].reputation = _newReputation;
        
        emit ModeratorReputationChanged(_moderator, previousReputation, _newReputation);
    }
    
    /**
     * @dev Set moderator active status
     * @param _active New active status
     */
    function setActiveStatus(bool _active) external {
        require(moderators[msg.sender].exists, "Not registered");
        
        if (moderators[msg.sender].active != _active) {
            moderators[msg.sender].active = _active;
            
            if (!_active) {
                _removeFromActiveModerators(msg.sender);
            } else {
                bool found = false;
                for (uint i = 0; i < activeModerators.length; i++) {
                    if (activeModerators[i] == msg.sender) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    activeModerators.push(msg.sender);
                }
            }
            
            emit ModeratorStatusChanged(msg.sender, _active);
        }
    }
    
    /**
     * @dev Internal function to remove address from active moderators
     * @param _moderator Moderator address to remove
     */
    function _removeFromActiveModerators(address _moderator) internal {
        for (uint i = 0; i < activeModerators.length; i++) {
            if (activeModerators[i] == _moderator) {
                activeModerators[i] = activeModerators[activeModerators.length - 1];
                activeModerators.pop();
                break;
            }
        }
    }
    
    /**
     * @dev Get moderator data
     * @param _moderator Moderator address
     */
    function getModeratorData(address _moderator) 
        external 
        view 
        returns (
            uint256 reputation,
            uint256 stake,
            bool active
        ) 
    {
        require(moderators[_moderator].exists, "Moderator doesn't exist");
        Moderator storage mod = moderators[_moderator];
        
        return (
            mod.reputation,
            mod.stake,
            mod.active
        );
    }
    
    /**
     * @dev Get active moderators count
     */
    function getActiveModeratorCount() external view returns (uint256) {
        return activeModerators.length;
    }
    
    /**
     * @dev Get active moderators with pagination
     * @param _offset Starting index
     * @param _limit Max number of entries to return
     */
    function getActiveModerators(uint256 _offset, uint256 _limit) 
        external 
        view 
        returns (address[] memory result) 
    {
        uint256 count = activeModerators.length;
        
        if (_offset >= count) {
            return new address[](0);
        }
        
        uint256 end = _offset + _limit;
        if (end > count) {
            end = count;
        }
        
        uint256 resultLength = end - _offset;
        result = new address[](resultLength);
        
        for (uint256 i = 0; i < resultLength; i++) {
            result[i] = activeModerators[_offset + i];
        }
        
        return result;
    }
    
    /**
     * @dev Sets the moderation contract address
     * @param _moderationContract Address of the moderation contract
     */
    function setModerationContract(address _moderationContract) external onlyOwner {
        moderationContract = _moderationContract;
    }
}