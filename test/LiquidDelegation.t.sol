// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

/* solhint-disable no-console */
import {BaseDelegationTest} from "test/BaseDelegation.t.sol";
import {LiquidDelegation} from "src/LiquidDelegation.sol";
import {LiquidDelegationV2} from "src/LiquidDelegationV2.sol";
import {NonRebasingLST} from "src/NonRebasingLST.sol";
import {BaseDelegation} from "src/BaseDelegation.sol";
import {WithdrawalQueue} from "src/WithdrawalQueue.sol";
import {IDelegation} from "src/IDelegation.sol";
import {Deposit} from "@zilliqa/zq2/deposit_v4.sol";
import {Console} from "src/Console.sol";
import {Vm} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

/* solhint-disable func-name-mixedcase */
contract LiquidDelegationTest is BaseDelegationTest {
    LiquidDelegationV2 internal delegation;
    NonRebasingLST internal lst;

    constructor() BaseDelegationTest() {
        oldImplementation = address(new LiquidDelegation());
        newImplementation = payable(new LiquidDelegationV2());
        initializerCall = abi.encodeWithSelector(
            LiquidDelegation.initialize.selector,
            owner,
            "LiquidStakingToken",
            "LST"
        );
        reinitializerCall = abi.encodeWithSelector(
            LiquidDelegationV2.reinitialize.selector
        );
    }

    function storeDelegation() internal override {
        delegation = LiquidDelegationV2(
            proxy
        );
        lst = NonRebasingLST(delegation.getLST());
        /*
        console.log("LST address: %s",
            address(lst)
        );
        //*/
    }

    function run(
        uint256 depositAmount,
        uint256 rewardsBeforeStaking,
        uint256 taxedRewardsBeforeStaking,
        uint256 delegatedAmount,
        uint8 numberOfDelegations,
        uint256 rewardsAccruedAfterEach,
        uint256 rewardsBeforeUnstaking,
        uint256 blocksUntil,
        DepositMode mode
    ) internal {
        delegation = LiquidDelegationV2(proxy);
        lst = NonRebasingLST(delegation.getLST());

        if (mode == DepositMode.DepositThenMigrate)
            migrate(BaseDelegation(delegation), depositAmount);
        else
            deposit(BaseDelegation(delegation), depositAmount, mode == DepositMode.DepositThenStake);

        vm.store(address(delegation), 0xfa57cbed4b267d0bc9f2cbdae86b4d1d23ca818308f873af9c968a23afadfd01, bytes32(taxedRewardsBeforeStaking));
        vm.deal(address(delegation), rewardsBeforeStaking);
        vm.deal(stakers[0], 100_000 ether);
        vm.startPrank(stakers[0]);

        Console.log("Deposit before staking: %s.%s%s ZIL",
            delegation.getStake()
        );

        Console.log("Rewards before staking: %s.%s%s ZIL",
            delegation.getRewards()
        );

        Console.log("Taxed rewards before staking: %s.%s%s ZIL",
            delegation.getTaxedRewards()
        );

        Console.log("Staker balance before staking: %s.%s%s ZIL",
            stakers[0].balance
        );

        Console.log("Staker balance before staking: %s.%s%s LST",
            lst.balanceOf(stakers[0])
        );

        Console.log("Total supply before staking: %s.%s%s LST", 
            lst.totalSupply()
        );

        uint256[2] memory ownerZIL = [uint256(0), 0];
        uint256 loggedAmount;
        uint256 loggedShares;
        uint256 totalShares;
        uint256 rewardsAfterStaking;
        uint256 taxedRewardsAfterStaking;
        uint256 rewardsDelta = rewardsBeforeStaking - taxedRewardsBeforeStaking;
        Vm.Log[] memory entries;

        for (uint8 j = 0; j < numberOfDelegations; j++) {
            console.log("staking %s --------------------------------", j + 1);

            vm.recordLogs();

            vm.expectEmit(
                true,
                false,
                false,
                false,
                address(delegation)
            );
            emit IDelegation.Staked(
                stakers[0],
                delegatedAmount,
                abi.encode(lst.totalSupply() * delegatedAmount / (delegation.getStake() + delegation.getRewards()))
            );

            ownerZIL[0] = delegation.owner().balance;

            delegation.stake{
                value: delegatedAmount
            }();

            // wait 2 epochs for the change to the deposit to take affect
            vm.roll(block.number + Deposit(delegation.DEPOSIT_CONTRACT()).blocksPerEpoch() * 2);

            ownerZIL[1] = delegation.owner().balance;

            entries = vm.getRecordedLogs();
            for (uint256 i = 0; i < entries.length; i++) {
                if (entries[i].topics[0] == keccak256("Staked(address,uint256,bytes)")) {
                    bytes memory x;
                    (loggedAmount, x) = abi.decode(entries[i].data, (uint256, bytes));
                    loggedShares = abi.decode(x, (uint256));
                    assertEq(loggedAmount, delegatedAmount, "staked amount mismatch");
                }
            }
            totalShares += loggedShares;

            Console.log("Owner commission after staking: %s.%s%s ZIL",
                ownerZIL[1] - ownerZIL[0]
            );
            assertEq(rewardsDelta * delegation.getCommissionNumerator() / delegation.DENOMINATOR(), ownerZIL[1] - ownerZIL[0], "commission mismatch after staking");

            Console.log("Deposit after staking: %s.%s%s ZIL",
                delegation.getStake()
            );

            rewardsAfterStaking = delegation.getRewards();
            Console.log("Rewards after staking: %s.%s%s ZIL",
                rewardsAfterStaking
            );

            taxedRewardsAfterStaking = delegation.getTaxedRewards();
            Console.log("Taxed rewards after staking: %s.%s%s ZIL",
                taxedRewardsAfterStaking
            );

            Console.log("Staker balance after staking: %s.%s%s ZIL",
                stakers[0].balance
            );

            Console.log("Staker balance after staking: %s.%s%s LST",
                lst.balanceOf(stakers[0])
            );

            Console.log("Total supply after staking: %s.%s%s LST",
                lst.totalSupply()
            );

            vm.deal(address(delegation), address(delegation).balance + rewardsAccruedAfterEach);
            rewardsDelta = delegation.getRewards() - taxedRewardsAfterStaking;
        }

        vm.deal(address(delegation), rewardsBeforeUnstaking);

        uint256 lstPrice = 10**18 * 1 ether * ((delegation.getStake() + delegation.getRewards() - (delegation.getRewards() - delegation.getTaxedRewards()) * delegation.getCommissionNumerator() / delegation.DENOMINATOR())) / lst.totalSupply();
        Console.log("LST price: %s.%s%s",
            lstPrice
        );
        assertEq(lstPrice / 10**18, delegation.getPrice(), "price mismatch");

        Console.log("LST value: %s.%s%s",
            totalShares * lstPrice / 10**18 / 1 ether
        );

        vm.recordLogs();

        vm.expectEmit(
            true,
            false,
            false,
            false,
            address(delegation)
        );
        emit IDelegation.Unstaked(
            stakers[0],
            (delegation.getStake() + delegation.getRewards()) * lst.balanceOf(stakers[0]) / lst.totalSupply(),
            abi.encode(lst.balanceOf(stakers[0]))
        );

        uint256[2] memory stakerLST = [lst.balanceOf(stakers[0]), 0];
        ownerZIL[0] = delegation.owner().balance;

        uint256 shares = mode != DepositMode.StakeThenDeposit ? lst.balanceOf(stakers[0]) : lst.balanceOf(stakers[0]) - depositAmount;
        assertEq(totalShares, shares, "staked shares balance mismatch");

        delegation.unstake(
            shares
        );

        // wait 2 epochs for the change to the deposit to take affect
        vm.roll(block.number + Deposit(delegation.DEPOSIT_CONTRACT()).blocksPerEpoch() * 2);

        stakerLST[1] = lst.balanceOf(stakers[0]);
        ownerZIL[1] = delegation.owner().balance;

        assertEq((rewardsBeforeUnstaking - taxedRewardsAfterStaking) * delegation.getCommissionNumerator() / delegation.DENOMINATOR(), ownerZIL[1] - ownerZIL[0], "commission mismatch after unstaking");

        entries = vm.getRecordedLogs();
        
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("Unstaked(address,uint256,bytes)")) {
                bytes memory x;
                (loggedAmount, x) = abi.decode(entries[i].data, (uint256, bytes));
                loggedShares = abi.decode(x, (uint256));
            } 
        }
        assertEq(totalShares * lstPrice / 10**18 / 1 ether, loggedAmount, "unstaked amount mismatch");
        assertEq(shares, loggedShares, "unstaked shares mismatch");
        assertEq(shares, stakerLST[0] - stakerLST[1], "shares balance mismatch");
        
        Console.log("Owner commission after unstaking: %s.%s%s ZIL", 
            ownerZIL[1] - ownerZIL[0]
        );

        Console.log("Deposit after unstaking: %s.%s%s ZIL",
            delegation.getStake()
        );

        uint256 rewardsAfterUnstaking = delegation.getRewards();
        Console.log("Rewards after unstaking: %s.%s%s ZIL",
            rewardsAfterUnstaking
        );

        uint256 taxedRewardsAfterUnstaking = delegation.getTaxedRewards();
        Console.log("Taxed rewards after unstaking: %s.%s%s ZIL",
            taxedRewardsAfterUnstaking
        );

        uint256 stakerBalanceAfterUnstaking = stakers[0].balance;
        Console.log("Staker balance after unstaking: %s.%s%s ZIL",
            stakerBalanceAfterUnstaking
        );

        Console.log("Staker balance after unstaking: %s.%s%s LST",
            lst.balanceOf(stakers[0])
        );

        Console.log("Total supply after unstaking: %s.%s%s LST", 
            lst.totalSupply()
        );

        vm.roll(block.number + blocksUntil);

        vm.recordLogs();

        uint256 unstakedAmount = loggedAmount; // the amount we logged on unstaking
        Console.log("Unstaked amount: %s.%s%s ZIL", unstakedAmount);

        vm.expectEmit(
            true,
            false,
            false,
            false,
            address(delegation)
        );
        emit IDelegation.Claimed(
            stakers[0],
            unstakedAmount,
            ""
        );

        uint256[2] memory stakerZIL = [stakers[0].balance, 0];
        ownerZIL[0] = delegation.owner().balance;

        delegation.claim();

        stakerZIL[1] = stakers[0].balance;
        ownerZIL[1] = delegation.owner().balance;

        entries = vm.getRecordedLogs();

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("Claimed(address,uint256,bytes)")) {
                (loggedAmount, ) = abi.decode(entries[i].data, (uint256,bytes));
            } 
        }
        assertEq(loggedAmount, unstakedAmount, "unstaked vs claimed amount mismatch");
        assertEq(loggedAmount, stakerZIL[1] - stakerZIL[0], "claimed amount vs staker balance mismatch");

        Console.log("Owner commission after claiming: %s.%s%s ZIL", 
            ownerZIL[1] - ownerZIL[0]
        );
        assertEq((rewardsAfterUnstaking - taxedRewardsAfterUnstaking) * delegation.getCommissionNumerator() / delegation.DENOMINATOR(), ownerZIL[1] - ownerZIL[0], "commission mismatch after claiming");

        Console.log("Deposit after claiming: %s.%s%s ZIL",
            delegation.getStake()
        );

        Console.log("Rewards after claiming: %s.%s%s ZIL",
            delegation.getRewards()
        );

        Console.log("Taxed rewards after claiming: %s.%s%s ZIL",
            delegation.getTaxedRewards()
        );

        Console.log("Staker balance after claiming: %s.%s%s ZIL",
            stakers[0].balance
        );
        assertEq(stakers[0].balance, stakerBalanceAfterUnstaking + unstakedAmount, "final staker balance mismatch");

        Console.log("Staker balance after claiming: %s.%s%s LST",
            lst.balanceOf(stakers[0])
        );

        Console.log("Total supply after claiming: %s.%s%s LST", 
            lst.totalSupply()
        );

    }

    // Test cases of depositing first and staking afterwards start here

    function test_DepositThenStake_LargeStake_Late_NoRewards_UnstakeAll() public {
        stakers[0] = 0x092E5E57955437876dA9Df998C96e2BE19341670;
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 10_000 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        run(
            depositAmount,
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod(), // after unstaking wait blocksUntil claiming
            DepositMode.DepositThenStake
        );
    }

    function test_DepositThenStake_LargeStake_Late_SmallValidator_OwnDeposit_OneYearOfRewards_UnstakeAll() public {
        stakers[0] = 0x092E5E57955437876dA9Df998C96e2BE19341670;
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 10_000 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        run(
            depositAmount,
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod(), // after unstaking wait blocksUntil claiming
            DepositMode.DepositThenStake
        );
    }

    function test_DepositThenStake_SmallStake_Late_SmallValidator_OwnDeposit_OneYearOfRewards_UnstakeAll() public {
        stakers[0] = 0x092E5E57955437876dA9Df998C96e2BE19341670;
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 100 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        run(
            depositAmount,
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod(), // after unstaking wait blocksUntil claiming
            DepositMode.DepositThenStake
        );
    }

    function test_DepositThenStake_LargeStake_Late_LargeValidator_OwnDeposit_OneYearOfRewards_UnstakeAll() public {
        stakers[0] = 0x092E5E57955437876dA9Df998C96e2BE19341670;
        uint256 depositAmount = 100_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 10_000 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        run(
            depositAmount,
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod(), // after unstaking wait blocksUntil claiming
            DepositMode.DepositThenStake
        );
    }

    function test_DepositThenStake_SmallStake_Late_LargeValidator_OwnDeposit_OneYearOfRewards_UnstakeAll() public {
        stakers[0] = 0x092E5E57955437876dA9Df998C96e2BE19341670;
        uint256 depositAmount = 100_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 100 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        run(
            depositAmount,
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod(), // after unstaking wait blocksUntil claiming
            DepositMode.DepositThenStake
        );
    }

    function test_DepositThenStake_LargeStake_Early_NoRewards_UnstakeAll() public {
        stakers[0] = 0x092E5E57955437876dA9Df998C96e2BE19341670;
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 10_000 ether;
        uint256 rewardsBeforeStaking = 1 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        run(
            depositAmount,
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod(), // after unstaking wait blocksUntil claiming
            DepositMode.DepositThenStake
        );
    }

    function test_DepositThenStake_LargeStake_Late_SmallValidator_DelegatedDeposit_OneYearOfRewards_UnstakeAll() public {
        stakers[0] = 0x092E5E57955437876dA9Df998C96e2BE19341670;
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 10_000 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        run(
            depositAmount,
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod(), // after unstaking wait blocksUntil claiming
            DepositMode.DepositThenStake
        );
    } 

    // Test cases of migrating a solo staker to a staking pool start here

    function test_DepositThenMigrate_LargeStake_Late_NoRewards_UnstakeAll() public {
        stakers[0] = 0x092E5E57955437876dA9Df998C96e2BE19341670;
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 10_000 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        run(
            depositAmount,
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod(), // after unstaking wait blocksUntil claiming
            DepositMode.DepositThenMigrate
        );
    }

    function test_DepositThenMigrate_LargeStake_Late_SmallValidator_OwnDeposit_OneYearOfRewards_UnstakeAll() public {
        stakers[0] = 0x092E5E57955437876dA9Df998C96e2BE19341670;
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 10_000 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        run(
            depositAmount,
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod(), // after unstaking wait blocksUntil claiming
            DepositMode.DepositThenMigrate
        );
    } 

    function test_DepositThenMigrate_SmallStake_Late_SmallValidator_OwnDeposit_OneYearOfRewards_UnstakeAll() public {
        stakers[0] = 0x092E5E57955437876dA9Df998C96e2BE19341670;
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 100 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        run(
            depositAmount,
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod(), // after unstaking wait blocksUntil claiming
            DepositMode.DepositThenMigrate
        );
    } 

    function test_DepositThenMigrate_LargeStake_Late_LargeValidator_OwnDeposit_OneYearOfRewards_UnstakeAll() public {
        stakers[0] = 0x092E5E57955437876dA9Df998C96e2BE19341670;
        uint256 depositAmount = 100_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 10_000 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        run(
            depositAmount,
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod(), // after unstaking wait blocksUntil claiming
            DepositMode.DepositThenMigrate
        );
    }

    function test_DepositThenMigrate_SmallStake_Late_LargeValidator_OwnDeposit_OneYearOfRewards_UnstakeAll() public {
        stakers[0] = 0x092E5E57955437876dA9Df998C96e2BE19341670;
        uint256 depositAmount = 100_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 100 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        run(
            depositAmount,
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod(), // after unstaking wait blocksUntil claiming
            DepositMode.DepositThenMigrate
        );
    }

    function test_DepositThenMigrate_LargeStake_Early_NoRewards_UnstakeAll() public {
        stakers[0] = 0x092E5E57955437876dA9Df998C96e2BE19341670;
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 10_000 ether;
        uint256 rewardsBeforeStaking = 1 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        run(
            depositAmount,
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod(), // after unstaking wait blocksUntil claiming
            DepositMode.DepositThenMigrate
        );
    }

    function test_DepositThenMigrate_LargeStake_Late_SmallValidator_DelegatedDeposit_OneYearOfRewards_UnstakeAll() public {
        stakers[0] = 0x092E5E57955437876dA9Df998C96e2BE19341670;
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 10_000 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        run(
            depositAmount,
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod(), // after unstaking wait blocksUntil claiming
            DepositMode.DepositThenMigrate
        );
    }

    // Test cases of staking first and depositing later start here

    function test_StakeThenDeposit_SmallStake_Late_SmallValidator_DelegatedDeposit_OneYearOfRewards_UnstakeAll() public {
        stakers[0] = 0x092E5E57955437876dA9Df998C96e2BE19341670;
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 100 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        run(
            depositAmount,
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod(), // after unstaking wait blocksUntil claiming
            DepositMode.StakeThenDeposit
        );
    }

    function test_StakeThenDeposit_LargeStake_Late_LargeValidator_DelegatedDeposit_OneYearOfRewards_UnstakeAll() public {
        stakers[0] = 0x092E5E57955437876dA9Df998C96e2BE19341670;
        uint256 depositAmount = 100_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 10_000 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        run(
            depositAmount,
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod(), // after unstaking wait blocksUntil claiming
            DepositMode.StakeThenDeposit
        );
    }

    function test_StakeThenDeposit_SmallStake_Late_LargeValidator_DelegatedDeposit_OneYearOfRewards_UnstakeAll() public {
        stakers[0] = 0x092E5E57955437876dA9Df998C96e2BE19341670;
        uint256 depositAmount = 100_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 100 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        run(
            depositAmount,
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod(), // after unstaking wait blocksUntil claiming
            DepositMode.StakeThenDeposit
        );
    }

    // Test cases of early staking start here

    function test_DepositThenStake_LargeStake_Early_SmallValidator_OwnDeposit_OneYearOfRewards_UnstakeAll() public {
        stakers[0] = 0x092E5E57955437876dA9Df998C96e2BE19341670;
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 10_000 ether;
        uint256 rewardsBeforeStaking = 1 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        run(
            depositAmount,
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod(), // after unstaking wait blocksUntil claiming
            DepositMode.DepositThenStake
        );
    }

    function test_DepositThenStake_SmallStake_Early_SmallValidator_OwnDeposit_OneYearOfRewards_UnstakeAll() public {
        stakers[0] = 0x092E5E57955437876dA9Df998C96e2BE19341670;
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 100 ether;
        uint256 rewardsBeforeStaking = 1 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        run(
            depositAmount,
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod(), // after unstaking wait blocksUntil claiming
            DepositMode.DepositThenStake
        );
    } 

    function test_DepositThenStake_LargeStake_Early_LargeValidator_OwnDeposit_OneYearOfRewards_UnstakeAll() public {
        stakers[0] = 0x092E5E57955437876dA9Df998C96e2BE19341670;
        uint256 depositAmount = 100_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 10_000 ether;
        uint256 rewardsBeforeStaking = 1 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        run(
            depositAmount,
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod(), // after unstaking wait blocksUntil claiming
            DepositMode.DepositThenStake
        );
    }

    function test_DepositThenStake_SmallStake_Early_LargeValidator_OwnDeposit_OneYearOfRewards_UnstakeAll() public {
        stakers[0] = 0x092E5E57955437876dA9Df998C96e2BE19341670;
        uint256 depositAmount = 100_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 100 ether;
        uint256 rewardsBeforeStaking = 1 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        run(
            depositAmount,
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod(), // after unstaking wait blocksUntil claiming
            DepositMode.DepositThenStake
        );
    } 

    // Additional test cases start here

    function test_DepositThenStake_ManyVsOneStake_UnstakeAll() public {
        stakers[0] = 0x092E5E57955437876dA9Df998C96e2BE19341670;
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 110_000_000 ether;
        uint256 delegatedAmount = 10_000 ether;
        uint256 rewardsBeforeStaking = 51_000 ether / uint256(60) * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        run(
            depositAmount,
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            9, // numberOfDelegations
            // 5s of rewards between the delegations; always check if
            // (numberOfDelegations - 1) * rewardsAccruedAfterEach <= rewardsBeforeUnstaking
            5 * 51_000 ether / uint256(3600) * depositAmount / totalDeposit, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 51_000 ether / uint256(60) * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod(), // after unstaking wait blocksUntil claiming
            DepositMode.DepositThenStake
        );
    }

    function test_DepositThenStake_OneVsManyStakes_UnstakeAll() public {
        stakers[0] = 0x092E5E57955437876dA9Df998C96e2BE19341670;
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 110_000_000 ether;
        uint256 delegatedAmount = 90_000 ether;
        uint256 rewardsBeforeStaking = 51_000 ether / uint256(60) * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        run(
            depositAmount,
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 51_000 ether / uint256(60) * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod(), // after unstaking wait blocksUntil claiming
            DepositMode.DepositThenStake
        );
    }

    function test_claimsAfterManyUnstakings() public {
        claimsAfterManyUnstakings(
            LiquidDelegationV2(proxy), //delegation
            20 //steps
        );
    }

}