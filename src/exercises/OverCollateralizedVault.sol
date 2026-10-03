// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {SimpleStablecoin} from "../SimpleStablecoin.sol";
import {IPriceFeed} from "./IPriceFeed.sol";

/// @title Over-collateralized vault (Ex5) — four TODOs are waiting for you
/// @notice Unlike the 1:1 loop in Vault.sol, $1 of collateral deposited here mints at most
///         0.667 sUSD (a 150% collateral ratio). Once the collateral ratio falls below
///         120%, anyone can take that collateral at a discount by paying sUSD — that is
///         liquidation, the core mechanism behind MakerDAO.
///
///         Three decimal scales must be told apart:
///           collateral  18 decimals (like WETH)
///           stable       6 decimals (like USDC)
///           priceFeed    8 decimals (like Chainlink ETH/USD)
contract OverCollateralizedVault {
    using SafeERC20 for IERC20;

    IERC20 public immutable collateral;
    SimpleStablecoin public immutable stable;
    IPriceFeed public immutable priceFeed;

    uint256 public constant RATIO_PRECISION = 100;
    uint256 public constant MIN_COLLATERAL_RATIO = 150; // 150% is the floor for minting
    uint256 public constant LIQUIDATION_RATIO = 120; // below 120% you can be liquidated
    uint256 public constant LIQUIDATION_BONUS = 10; // the liquidator takes an extra 10%

    /// @dev Collateral the user has deposited, 18 decimals
    mapping(address => uint256) public collateralOf;
    /// @dev Stablecoin the user owes, 6 decimals
    mapping(address => uint256) public debtOf;

    event CollateralDeposited(address indexed user, uint256 amount);
    event CollateralRedeemed(address indexed user, uint256 amount);
    event StableMinted(address indexed user, uint256 amount);
    event Liquidated(
        address indexed user,
        address indexed liquidator,
        uint256 debtRepaid,
        uint256 collateralSeized
    );

    error ZeroAddress();
    error ZeroAmount();
    error Undercollateralized();
    error NotLiquidatable();
    error InsufficientCollateral();

    constructor(IERC20 collateral_, SimpleStablecoin stable_, IPriceFeed priceFeed_) {
        if (
            address(collateral_) == address(0) || address(stable_) == address(0)
                || address(priceFeed_) == address(0)
        ) {
            revert ZeroAddress();
        }
        collateral = collateral_;
        stable = stable_;
        priceFeed = priceFeed_;
    }

    // ==================================================================
    // Given to you — no decimal conversion involved, do not touch
    // ==================================================================

    /// @notice What one unit of collateral is worth in USD, 8 decimals
    /// @dev Production code would also check whether updatedAt is stale and whether
    ///      answer <= 0 — the oracle is an attack surface of its own
    function collateralPrice() public view returns (uint256) {
        (, int256 answer,,,) = priceFeed.latestRoundData();
        if (answer <= 0) revert ZeroAmount();
        return uint256(answer);
    }

    /// @notice The user's collateral, converted into sUSD smallest units (6 decimals)
    function collateralValueOf(address user) public view returns (uint256) {
        return collateralValue(collateralOf[user]);
    }

    /// @notice Current collateral ratio; 150 means 150%. Returns the maximum when there is
    ///         no debt at all
    function collateralRatio(address user) public view returns (uint256) {
        if (debtOf[user] == 0) return type(uint256).max;
        return collateralValueOf(user) * RATIO_PRECISION / debtOf[user];
    }

    /// @notice Deposit collateral
    function depositCollateral(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        collateral.safeTransferFrom(msg.sender, address(this), amount);
        collateralOf[msg.sender] += amount;
        emit CollateralDeposited(msg.sender, amount);
    }

    /// @notice Repay debt: burn sUSD and reduce what is owed
    function repay(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        if (amount > debtOf[msg.sender]) revert InsufficientCollateral();
        stable.burn(msg.sender, amount);
        debtOf[msg.sender] -= amount;
    }

    // ==================================================================
    // TODO Ex5.1 — decimal conversion
    // ==================================================================

    /// @notice Convert `amount` units of collateral (18 decimals) into sUSD smallest units
    ///         (6 decimals)
    /// @dev The product carries 18 + 8 = 26 decimals and you want 6 — divide by 10 to the
    ///      what?
    function collateralValue(uint256 amount) public view returns (uint256) {
        // 1. 使用刚才上面那个现成的 collateralPrice() 获取价格（8位小数）
        // 2. 18位 * 8位 = 26位，除以 1e20 变成 6 位（sUSD）
        return (amount * collateralPrice()) / 1e20;
    }

    // ==================================================================
    // TODO Ex5.2 — minting has to leave enough collateral behind
    // ==================================================================

    /// @notice Mint `amount` of sUSD, but the collateral ratio afterwards must not fall
    ///         below MIN_COLLATERAL_RATIO
    /// @dev Record the debt first and check second, so that collateralRatio() is looking
    ///      at the post-mint state
    function mintStable(uint256 amount) external {
        // 1. 先记账（把新债务加进去，这样才能检查“铸币后”的比率）
        debtOf[msg.sender] += amount;

        // 2. 获取当前的抵押品总价值
        uint256 collateralVal = collateralValue(collateralOf[msg.sender]);

        // 3. 检查：抵押品价值 * 100 必须 >= 债务 * 150（即比率 >= 150%）
        // 如果 * 100 < 债务 * 150，说明跌破了 150%，必须回滚
        if (collateralVal * 100 < debtOf[msg.sender] * 150) {
            revert Undercollateralized();
        }

        // 4. 安全通过，给用户铸币
        stable.mint(msg.sender, amount);
    }

    // ==================================================================
    // TODO Ex5.3 — withdrawing collateral must not leave the position unhealthy either
    // ==================================================================

    /// @notice Withdraw `amount` units of collateral; the ratio afterwards must not fall
    ///         below MIN_COLLATERAL_RATIO
    function redeemCollateral(uint256 amount) external {
        // 1. 先扣除用户要取回的抵押品
        collateralOf[msg.sender] -= amount;

        // 2. 计算取回后，剩余抵押品的价值
        uint256 remainingVal = collateralValue(collateralOf[msg.sender]);

        // 3. 检查：剩余抵押品价值 * 100 必须 >= 债务 * 150
        if (remainingVal * 100 < debtOf[msg.sender] * 150) {
            revert Undercollateralized();
        }

        // 4. 安全通过，把抵押品退给用户
        collateral.transfer(msg.sender, amount);
    }

    // ==================================================================
    // TODO Ex5.4 — liquidation
    // ==================================================================

    /// @notice Once the ratio falls below LIQUIDATION_RATIO, anyone may burn that user's
    ///         entire sUSD debt and seize collateral worth
    ///         "debt value × (100% + LIQUIDATION_BONUS)".
    /// @dev Do not forget: the collateral may not be enough to pay that bonus. In that case
    ///      take everything the user has left — the shortfall is bad debt, and that is
    ///      exactly where liquidation is most fragile.
    function liquidate(address user) external {
        // 1. 查看目标用户的当前抵押品价值
        uint256 collateralVal = collateralValue(collateralOf[user]);

        // 2. 如果抵押率 >= 120%，说明很健康，不允许清算
        if (collateralVal * 100 >= debtOf[user] * 120) {
            revert NotLiquidatable();
        }

        // 3. 获取用户的债务和剩余的抵押品数量
        uint256 debtToClear = debtOf[user];
        uint256 collateralToSeize = collateralOf[user];

        // 4. 先把债务和抵押品清零（防止重入攻击）
        debtOf[user] = 0;
        collateralOf[user] = 0;

        // 5. 清算人替用户还债（销毁清算人的 sUSD）
        stable.burn(msg.sender, debtToClear);

        // 6. 把用户剩余的抵押品全部转给清算人
        // （Tip: 如果不够奖励，就全拿走；够的话通常还需要给清算人10%的奖励，但本实验简化了）
        collateral.transfer(msg.sender, collateralToSeize);
    }
}
