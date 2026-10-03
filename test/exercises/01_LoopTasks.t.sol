// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {MockUSDC} from "../../src/MockUSDC.sol";
import {SimpleStablecoin} from "../../src/SimpleStablecoin.sol";
import {Vault} from "../../src/Vault.sol";

/// @title Ex2 + Ex4 — hands-on tasks: turn red into green
/// @notice Every `assertTrue(false, "TODO ...")` below is a placeholder. Write the real
///         assertion, watch the test go green, and that exercise is done.
///
///         Acceptance: make exercise (it should be red until you are finished)
///         Do not open test/Stablecoin.t.sol — it contains the answers. Write yours
///         first, and only look once you are stuck.
contract LoopTasksTest is Test {
    MockUSDC internal usdc;
    SimpleStablecoin internal stable;
    Vault internal vault;

    address internal admin = address(this);
    address internal alice = makeAddr("alice");
    address internal attacker = makeAddr("attacker");

    function setUp() public {
        usdc = new MockUSDC();
        stable = new SimpleStablecoin(admin);
        vault = new Vault(usdc, stable);
        stable.grantRole(stable.MINTER_ROLE(), address(vault));
    }

    // ==================================================================
    // Ex2 · the decimals trap: a 6-decimal stablecoin meets 18-decimal intuition
    // ==================================================================

    /// @dev For any legitimate amount x, totalSupply() must grow by exactly x after
    ///      deposit(x). Hint: use vm.assume to rule out x == 0, and faucet alice enough
    ///      usdc first.
    function test_Ex2_DepositIncreasesSupplyByExactly(uint96 raw) public {
        // 将随机数转换成一个合理的金额（最高 100 万 USDC）
        uint256 amount = uint256(raw) % 1_000_000e6;
        
        // 用 vm.assume 排除掉金额为 0 的情况，否则存款会失败
        vm.assume(amount > 0);

        // 记录存款前的总供应量
        uint256 initialSupply = stable.totalSupply();

        // 1. 去水龙头领取对应的 mUSDC（给自己，即 address(this)）
        usdc.faucet(address(this), amount);

        // 2. 授权金库，允许它使用你的 mUSDC
        usdc.approve(address(vault), amount);

        // 3. 存入金库，这会铸造等量的 sUSD
        vault.deposit(amount);

        // 4. 断言：总供应量必须精确增加 amount
        assertEq(stable.totalSupply(), initialSupply + amount, "Supply did not increase by exactly amount");
    }

    /// @dev Run deposit with 1000e18 instead of 1000e6, see what happens, then assert what
    ///      you observed. MockUSDC has 6 decimals — 1000e18 is one billion USDC.
    ///      There is no expected answer here; the point is that you run it yourself and
    ///      read the numbers.
    function test_Ex2_DecimalsTrap() public {
        // 你习惯性地用了 18 位小数的写法，但 MockUSDC 其实是 6 位小数
        uint256 trapAmount = 1000e18; 
        
        uint256 initialSupply = stable.totalSupply();

        // 1. 去水龙头领 1000e18 个最小单位的 mUSDC
        usdc.faucet(address(this), trapAmount);

        // 2. 授权金库
        usdc.approve(address(vault), trapAmount);

        // 3. 存入金库。注意：这里绝对不会 revert，因为系统只是忠实执行你的指令
        vault.deposit(trapAmount);

        // 4. 断言：不变量依然成立，供应量确实增加了 trapAmount（系统并没有算错，是你输入错了）
        assertEq(stable.totalSupply(), initialSupply + trapAmount, "The invariant still holds, but the amount is off by 10^12");
    }

    // ==================================================================
    // Ex4 · permissions and pausing: where the guard is, who holds the key
    // ==================================================================

    /// @dev The attacker has no MINTER_ROLE, so calling mint directly must revert. Use
    ///      vm.expectRevert + abi.encodeWithSelector to pin down the exact error.
    function test_Ex4_Mint_RevertsForNonMinter() public {
        vm.prank(alice); // 下一个调用来自 alice
        vm.expectRevert(); // 预期会 revert
        stable.mint(alice, 100e6); // 尝试为自己铸币
    }

    /// @dev After pause(), an ordinary transfer must revert
    function test_Ex4_Pause_BlocksTransfers() public {
        // 1. 先给 alice 一点币，方便她进行转账
        vm.prank(admin);
        stable.mint(alice, 100e6);

        // 2. 管理员暂停合约
        vm.prank(admin);
        stable.pause();

        // 3. alice 尝试向别人转账，预期失败
        vm.prank(alice);
        vm.expectRevert();
        stable.transfer(address(0x123), 10e6);
    }

    /// @dev What pause() freezes is _update, so redemption is frozen along with everything
    ///      else — why is that bad news in a real crisis?
    ///      (This is STUDENT-QUESTIONS.md B1 and B2.)
    function test_Ex4_Pause_BlocksRedeem() public {
        // 1. alice 存钱，拿到 sUSD
        vm.startPrank(alice);
        usdc.faucet(alice, 100e6);
        usdc.approve(address(vault), 100e6);
        vault.deposit(100e6);
        vm.stopPrank();

        // 2. 管理员暂停合约
        vm.prank(admin);
        stable.pause();

        // 3. alice 尝试赎回，预期失败
        vm.prank(alice);
        vm.expectRevert();
        vault.redeem(100e6);
    }

    /// @dev An attacker cannot burn someone else's balance
    function test_Ex4_AttackerCannotBurnOthersBalance() public {
        // 1. 给 alice 一些币
        vm.prank(admin);
        stable.mint(alice, 100e6);

        // 2. 攻击者尝试直接销毁 alice 的余额，预期失败
        vm.prank(attacker);
        vm.expectRevert();
        stable.burn(alice, 100e6);
    }

    /// @dev ...but the vault can, because it holds MINTER_ROLE and burn() answers to that
    ///      same role. This test proves the backdoor exists; it does not justify it.
    function test_Ex4_VaultHoldsTheKey_CanBurnAnyonesBalance() public {
        // 1. 给 alice 一些币
        vm.prank(admin);
        stable.mint(alice, 100e6);

        // 2. 伪装成金库（金库有 MINTER_ROLE）
        vm.prank(address(vault));
        stable.burn(alice, 100e6); // 直接销毁，这次不报错

        // 3. 验证 alice 的余额归零
        assertEq(stable.balanceOf(alice), 0);
    }
}
