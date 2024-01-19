import {IERC20Minimal} from "v4-core/contracts/interfaces/external/IERC20Minimal.sol";
import {RewardsDistributionRecipient} from "./RewardsDistributionRecipient.sol";
import {SafeMath} from "v4-core-last/lib/openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import {SafeMath} from "v4-core-last/lib/openzeppelin-contracts/contracts/utils/math/SafeMath.sol";

contract StakingRewards is RewardsDistributionRecipient {
    using SafeMath for uint256;

    error CallerNotRewardsDistribution();

    /* ========== STATE VARIABLES ========== */

    IERC20Minimal public rewardsToken;
    uint256 public periodFinish = 0;
    uint256 public rewardRate = 0;
    uint256 public rewardsDuration = 60 days;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    uint256 private _totalSupply;
    mapping(address => uint256) internal _balances;

    /* ========== CONSTRUCTOR ========== */

    // NOTE: Removes stakingToken from the original constructor (https://github.com/Uniswap/liquidity-staker/blob/3edce550aeeb7b0c17a10701ff4484d6967e345f/contracts/StakingRewards.sol#L35)
    // This example will not use any staking token, instead it will use lliquidity directly
    constructor(IERC20Minimal _rewardsToken, address _rewardsDistribution) {
        rewardsToken = _rewardsToken;
        rewardsDistribution = _rewardsDistribution;
    }

    /* ========== VIEWS ========== */

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish; 
    }

    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return rewardPerTokenStored.add(
            lastTimeRewardApplicable().sub(lastUpdateTime).mul(rewardRate).mul(1e18).div(_totalSupply)
        );
    }

    function earned(address account) public view returns (uint256) {
        return _balances[account].mul(rewardPerToken().sub(userRewardPerTokenPaid[account])).div(1e18).add(
            rewards[account]
        );
    }

    function getRewardForDuration() external view returns (uint256) {
        return rewardRate.mul(rewardsDuration);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function _stake(uint256 _amount, address _user) internal {
        updateReward(_user);
        _totalSupply = _totalSupply + _amount;
        _balances[_user] = _balances[_user].add(_amount);
        emit Staked(_user, _amount);
    }

    function _withdraw(uint256 _amount, address _user) internal {
        _totalSupply = _totalSupply - _amount;
        _balances[_user] = _balances[_user].sub(_amount);
        emit Withdrawn(_user, _amount);
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

    function exit() external {
        _withdraw(_balances[msg.sender], msg.sender);
        getReward();
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function notifyRewardAmount(uint256 reward) external override onlyRewardsDistribution {
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

    /* ========== MODIFIERS ========== */

    function updateReward(address account) private {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
    }

    /* ========== EVENTS ========== */

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
}
