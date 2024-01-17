import {IERC20Minimal} from "v4-core/contracts/interfaces/external/IERC20Minimal.sol";
import "forge-std/Test.sol";

contract LiquidityStaker {
    error CallerNotRewardsDistribution();

    /* ========== STATE VARIABLES ========== */

    IERC20Minimal public rewardsToken;
    uint256 public periodFinish = 0;
    uint256 public rewardRate = 0;
    uint256 public rewardsDuration = 60 days;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    /* ========== EVENTS ========== */

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;
    address public rewardsDistribution;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    mapping(address => uint256) public liquidityStakedPerUser;

    constructor(IERC20Minimal _rewardsToken, address _rewardsDistribution) {
        rewardsToken = _rewardsToken;
        rewardsDistribution = _rewardsDistribution;
    }

    modifier onlyRewardsDistribution() {
        if (msg.sender != rewardsDistribution) revert CallerNotRewardsDistribution();
        _;
    }

    function __stake(uint256 _amount, address _user) internal {
        require(_amount > 0, "Cannot stake 0");
        updateReward(_user);
        _totalSupply = _totalSupply + _amount;
        liquidityStakedPerUser[_user] = liquidityStakedPerUser[_user] + _amount;
        emit Staked(_user, _amount);
    }

    function __withdraw(uint256 _amount, address _user) internal {
        _totalSupply = _totalSupply - _amount;
        liquidityStakedPerUser[_user] = liquidityStakedPerUser[_user] - _amount;
        emit Withdrawn(_user, _amount);
    }

    function notifyRewardAmount(uint256 reward) external onlyRewardsDistribution {
        updateReward(address(0));

        if (block.timestamp >= periodFinish) {
            rewardRate = reward / rewardsDuration;
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            rewardRate = (reward + leftover) / rewardsDuration;
        }

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        uint256 balance = rewardsToken.balanceOf(address(this));
        require(rewardRate <= balance / rewardsDuration, "Provided reward too high");

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + rewardsDuration;
        emit RewardAdded(reward);
    }

    function updateReward(address account) private {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
    }

    // TODO: REMEMBER CALLING  NON REENTRANT
    function getReward() public {
        updateReward(msg.sender);
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardsToken.transfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    /////////////////////////////////
    ////////   Rewards   ///////////
    ////////////////////////////////

    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return rewardPerTokenStored + ((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18 / _totalSupply);
    }

    function earned(address account) public view returns (uint256) {
        uint256 rewardPerTokenDiff = rewardPerToken() - userRewardPerTokenPaid[account];
        uint256 earnedRewards = liquidityStakedPerUser[account] * rewardPerTokenDiff / 1e18;
        return earnedRewards + rewards[account];
    }

    function getRewardForDuration() external view returns (uint256) {
        return rewardRate * rewardsDuration;
    }
}
