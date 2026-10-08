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
        // Convert the random number into a reasonable amount of money (up to 1 million USDC)
        uint256 amount = uint256(raw) % 1_000_000e6;
        
        // Use vm.assume to exclude the case where the amount is 0, otherwise the deposit will fail
        vm.assume(amount > 0);

        // Record the total supply before the deposit
        uint256 initialSupply = stable.totalSupply();

        // 1. Go to the faucet to claim the corresponding mUSDC (for yourself, i.e. address(this))
        usdc.faucet(address(this), amount);

        // 2. Authorize the vault to use your mUSDC
        usdc.approve(address(vault), amount);

        // 3. Deposit into the vault, and an equivalent amount of sUSD will be minted
        vault.deposit(amount);

        // 4. Assert: The total supply must be increased by exactly amount
        assertEq(stable.totalSupply(), initialSupply + amount, "Supply did not increase by exactly amount");
    }

    /// @dev Run deposit with 1000e18 instead of 1000e6, see what happens, then assert what
    ///      you observed. MockUSDC has 6 decimals — 1000e18 is one billion USDC.
    ///      There is no expected answer here; the point is that you run it yourself and
    ///      read the numbers.
    function test_Ex2_DecimalsTrap() public {
        // MockUSDC actually has 6 decimal
        uint256 trapAmount = 1000e18; 
        
        uint256 initialSupply = stable.totalSupply();

        // 1. Go to the faucet and claim 1000e18 minimum units of mUSDC
        usdc.faucet(address(this), trapAmount);

        // 2. Authorized Vault
        usdc.approve(address(vault), trapAmount);

        // 3. Deposit into the vault.
        vault.deposit(trapAmount);

        // 4. The invariant still holds, and the supply indeed increased by trapAmount
        assertEq(stable.totalSupply(), initialSupply + trapAmount, "The invariant still holds, but the amount is off by 10^12");
    }

    // ==================================================================
    // Ex4 · permissions and pausing: where the guard is, who holds the key
    // ==================================================================

    /// @dev The attacker has no MINTER_ROLE, so calling mint directly must revert. Use
    ///      vm.expectRevert + abi.encodeWithSelector to pin down the exact error.
    function test_Ex4_Mint_RevertsForNonMinter() public {
        vm.prank(alice); // The next call comes from Alice
        vm.expectRevert(); // expected to revert
        stable.mint(alice, 100e6); // Try to mint coins for yourself
    }

    /// @dev After pause(), an ordinary transfer must revert
    function test_Ex4_Pause_BlocksTransfers() public {
        // 1. Give Alice some coins first to facilitate her transfer
        vm.prank(admin);
        stable.mint(alice, 100e6);

        // 2. The administrator has suspended the contract
        vm.prank(admin);
        stable.pause();

        // 3. Alice attempts to transfer money to someone else, but anticipates failure
        vm.prank(alice);
        vm.expectRevert();
        stable.transfer(address(0x123), 10e6);
    }

    /// @dev What pause() freezes is _update, so redemption is frozen along with everything
    ///      else — why is that bad news in a real crisis?
    ///      (This is STUDENT-QUESTIONS.md B1 and B2.)
    function test_Ex4_Pause_BlocksRedeem() public {
        // 1. Alice saves money and obtains sUSD
        vm.startPrank(alice);
        usdc.faucet(alice, 100e6);
        usdc.approve(address(vault), 100e6);
        vault.deposit(100e6);
        vm.stopPrank();

        // 2. The administrator suspends the contract
        vm.prank(admin);
        stable.pause();

        // 3. Alice attempts to redeem, but expects failure
        vm.prank(alice);
        vm.expectRevert();
        vault.redeem(100e6);
    }

    /// @dev An attacker cannot burn someone else's balance
    function test_Ex4_AttackerCannotBurnOthersBalance() public {
        // 1. Give Alice some coins
        vm.prank(admin);
        stable.mint(alice, 100e6);

        // 2. The attacker attempts to directly deplete Alice's balance, anticipating failure
        vm.prank(attacker);
        vm.expectRevert();
        stable.burn(alice, 100e6);
    }

    /// @dev ...but the vault can, because it holds MINTER_ROLE and burn() answers to that
    ///      same role. This test proves the backdoor exists; it does not justify it.
    function test_Ex4_VaultHoldsTheKey_CanBurnAnyonesBalance() public {
        // 1. Give Alice some coins
        vm.prank(admin);
        stable.mint(alice, 100e6);

        // 2. Disguise as a vault(the vault has MINTER_ROLE)
        vm.prank(address(vault));
        stable.burn(alice, 100e6); // Destroy directly, no error reporting this time

        // 3. Verify that Alice's balance is reset to zero
        assertEq(stable.balanceOf(alice), 0);
    }
}
