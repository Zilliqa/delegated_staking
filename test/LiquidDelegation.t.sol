// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.28;

/* solhint-disable no-console */
import { Deposit } from "@zilliqa/zq2/deposit_v5.sol";
import { Vm } from "forge-std/Test.sol";
import { Console } from "script/Console.s.sol";
import { Console } from "script/Console.s.sol";
import { BaseDelegation } from "src/BaseDelegation.sol";
import { IDelegation } from "src/IDelegation.sol";
import { LiquidDelegation } from "src/LiquidDelegation.sol";
import { NonRebasingLST } from "src/NonRebasingLST.sol";
import { WithdrawalQueue } from "src/WithdrawalQueue.sol";
import { BaseDelegationTest } from "test/BaseDelegation.t.sol";

/* solhint-disable func-name-mixedcase */
contract LiquidDelegationTest is BaseDelegationTest {

    LiquidDelegation[] internal delegations;
    LiquidDelegation internal delegation;
    NonRebasingLST[] internal lsts;
    NonRebasingLST internal lst;

    constructor() BaseDelegationTest() {
        implementation = address(new LiquidDelegation());
        initializerCall = abi.encodeWithSelector(
            LiquidDelegation.initialize.selector,
            owner,
            "LiquidStakingToken",
            "LST"
        );
    }

    function storeDelegation() internal override {
        delegation = LiquidDelegation(
            proxy
        );
        lst = NonRebasingLST(delegation.getLST());
        /*
        Console.log("LST address: %s",
            address(lst)
        );
        //*/
        delegations.push(delegation);
        lsts.push(lst);
    }

    function run(
        uint256 rewardsBeforeStaking,
        uint256 taxedRewardsBeforeStaking,
        uint256 delegatedAmount,
        uint8 numberOfDelegations,
        uint256 rewardsAccruedAfterEach,
        uint256 rewardsBeforeUnstaking,
        uint256 blocksUntil
    ) internal returns(
        uint256[2] memory ownerZIL,
        uint256 loggedAmount,
        uint256 loggedShares,
        uint256 totalShares,
        uint256 rewardsAfterStaking,
        uint256 taxedRewardsAfterStaking,
        uint256 rewardsDelta,
        uint256 lstBalanceBefore,
        uint256 lstPrice,
        uint256[2] memory stakerLST,
        uint256 shares,
        uint256 rewardsAfterUnstaking,
        uint256 taxedRewardsAfterUnstaking,
        uint256 stakerBalanceAfterUnstaking,
        uint256 unstakedAmount,
        uint256[2] memory stakerZIL
    ) {
        // staker[1] and staker[2] participated in fundraising
        uint256 stakerIndex = 1;
        vm.store(address(delegation), 0xfa57cbed4b267d0bc9f2cbdae86b4d1d23ca818308f873af9c968a23afadfd01, bytes32(taxedRewardsBeforeStaking));
        vm.deal(address(delegation), rewardsBeforeStaking);
        vm.deal(stakers[stakerIndex], 100_000 ether);
        vm.startPrank(stakers[stakerIndex]);

        Console.log18("Deposit before staking: %s.%s%s ZIL",
            delegation.getStake()
        );

        Console.log18("Rewards before staking: %s.%s%s ZIL",
            delegation.getRewards()
        );

        Console.log18("Taxed rewards before staking: %s.%s%s ZIL",
            delegation.getTaxedRewards()
        );

        Console.log18("Staker balance before staking: %s.%s%s ZIL",
            stakers[stakerIndex].balance
        );

        Console.log18("Staker balance before staking: %s.%s%s LST",
            lst.balanceOf(stakers[stakerIndex])
        );

        Console.log18("Total supply before staking: %s.%s%s LST", 
            lst.totalSupply()
        );

        ownerZIL = [uint256(0), 0];
        rewardsDelta = rewardsBeforeStaking - taxedRewardsBeforeStaking;
        // will be non-zero if the staker participated in fundraising
        lstBalanceBefore = lst.balanceOf(stakers[stakerIndex]);
        Vm.Log[] memory entries;

        for (uint8 j = 0; j < numberOfDelegations; j++) {
            Console.log("staking %s --------------------------------", j + 1);

            vm.recordLogs();

            vm.expectEmit(
                true,
                false,
                false,
                false,
                address(delegation)
            );
            emit IDelegation.Staked(
                stakers[stakerIndex],
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

            Console.log18("Owner commission after staking: %s.%s%s ZIL",
                ownerZIL[1] - ownerZIL[0]
            );
            assertEq(rewardsDelta * delegation.getCommissionNumerator() / delegation.DENOMINATOR(), ownerZIL[1] - ownerZIL[0], "commission mismatch after staking");

            Console.log18("Deposit after staking: %s.%s%s ZIL",
                delegation.getStake()
            );

            rewardsAfterStaking = delegation.getRewards();
            Console.log18("Rewards after staking: %s.%s%s ZIL",
                rewardsAfterStaking
            );

            taxedRewardsAfterStaking = delegation.getTaxedRewards();
            Console.log18("Taxed rewards after staking: %s.%s%s ZIL",
                taxedRewardsAfterStaking
            );

            Console.log18("Staker balance after staking: %s.%s%s ZIL",
                stakers[stakerIndex].balance
            );

            Console.log18("Staker balance after staking: %s.%s%s LST",
                lst.balanceOf(stakers[stakerIndex])
            );

            Console.log18("Total supply after staking: %s.%s%s LST",
                lst.totalSupply()
            );

            vm.deal(address(delegation), address(delegation).balance + rewardsAccruedAfterEach);
            rewardsDelta = delegation.getRewards() - taxedRewardsAfterStaking;
        }

        vm.deal(address(delegation), rewardsBeforeUnstaking);

        lstPrice = 10**18 * 1 ether * ((delegation.getStake() + delegation.getRewards() - (delegation.getRewards() - delegation.getTaxedRewards()) * delegation.getCommissionNumerator() / delegation.DENOMINATOR())) / lst.totalSupply();
        Console.log18("LST price: %s.%s%s",
            lstPrice
        );
        assertEq(lstPrice / 10**18, delegation.getPrice(), "price mismatch");

        Console.log18("LST value: %s.%s%s",
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
            stakers[stakerIndex],
            (delegation.getStake() + delegation.getRewards()) * lst.balanceOf(stakers[stakerIndex]) / lst.totalSupply(),
            abi.encode(lst.balanceOf(stakers[stakerIndex]))
        );

        stakerLST = [lst.balanceOf(stakers[stakerIndex]), 0];
        ownerZIL[0] = delegation.owner().balance;

        shares = lst.balanceOf(stakers[stakerIndex]) - lstBalanceBefore;
        assertEq(totalShares, shares, "staked shares balance mismatch");

        delegation.unstake(
            shares
        );

        // wait 2 epochs for the change to the deposit to take affect
        vm.roll(block.number + Deposit(delegation.DEPOSIT_CONTRACT()).blocksPerEpoch() * 2);

        stakerLST[1] = lst.balanceOf(stakers[stakerIndex]);
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
        
        Console.log18("Owner commission after unstaking: %s.%s%s ZIL", 
            ownerZIL[1] - ownerZIL[0]
        );

        Console.log18("Deposit after unstaking: %s.%s%s ZIL",
            delegation.getStake()
        );

        rewardsAfterUnstaking = delegation.getRewards();
        Console.log18("Rewards after unstaking: %s.%s%s ZIL",
            rewardsAfterUnstaking
        );

        taxedRewardsAfterUnstaking = delegation.getTaxedRewards();
        Console.log18("Taxed rewards after unstaking: %s.%s%s ZIL",
            taxedRewardsAfterUnstaking
        );

        stakerBalanceAfterUnstaking = stakers[stakerIndex].balance;
        Console.log18("Staker balance after unstaking: %s.%s%s ZIL",
            stakerBalanceAfterUnstaking
        );

        Console.log18("Staker balance after unstaking: %s.%s%s LST",
            lst.balanceOf(stakers[stakerIndex])
        );

        Console.log18("Total supply after unstaking: %s.%s%s LST", 
            lst.totalSupply()
        );

        vm.roll(block.number + blocksUntil);

        vm.recordLogs();

        unstakedAmount = loggedAmount; // the amount we logged on unstaking
        Console.log18("Unstaked amount: %s.%s%s ZIL", unstakedAmount);

        vm.expectEmit(
            true,
            false,
            false,
            false,
            address(delegation)
        );
        emit IDelegation.Claimed(
            stakers[stakerIndex],
            unstakedAmount,
            ""
        );

        stakerZIL = [stakers[stakerIndex].balance, 0];
        ownerZIL[0] = delegation.owner().balance;

        delegation.claim();

        stakerZIL[1] = stakers[stakerIndex].balance;
        ownerZIL[1] = delegation.owner().balance;

        entries = vm.getRecordedLogs();

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("Claimed(address,uint256,bytes)")) {
                (loggedAmount, ) = abi.decode(entries[i].data, (uint256,bytes));
            } 
        }
        assertEq(loggedAmount, unstakedAmount, "unstaked vs claimed amount mismatch");
        assertEq(loggedAmount, stakerZIL[1] - stakerZIL[0], "claimed amount vs staker balance mismatch");

        Console.log18("Owner commission after claiming: %s.%s%s ZIL", 
            ownerZIL[1] - ownerZIL[0]
        );
        assertEq((rewardsAfterUnstaking - taxedRewardsAfterUnstaking) * delegation.getCommissionNumerator() / delegation.DENOMINATOR(), ownerZIL[1] - ownerZIL[0], "commission mismatch after claiming");

        Console.log18("Deposit after claiming: %s.%s%s ZIL",
            delegation.getStake()
        );

        Console.log18("Rewards after claiming: %s.%s%s ZIL",
            delegation.getRewards()
        );

        Console.log18("Taxed rewards after claiming: %s.%s%s ZIL",
            delegation.getTaxedRewards()
        );

        Console.log18("Staker balance after claiming: %s.%s%s ZIL",
            stakers[stakerIndex].balance
        );
        assertEq(stakers[stakerIndex].balance, stakerBalanceAfterUnstaking + unstakedAmount, "final staker balance mismatch");

        Console.log18("Staker balance after claiming: %s.%s%s LST",
            lst.balanceOf(stakers[stakerIndex])
        );

        Console.log18("Total supply after claiming: %s.%s%s LST", 
            lst.totalSupply()
        );

    }

    // Test cases of depositing first and staking afterwards start here

    function test_Bootstrapping_LargeStake_Late_SmallValidator_OneYearOfRewards_UnstakeAll() public {
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 10_000 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log18("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
    }

    function test_Bootstrapping_SmallStake_Late_SmallValidator_OneYearOfRewards_UnstakeAll() public {
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 100 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log18("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
    }

    function test_Bootstrapping_LargeStake_Late_LargeValidator_OneYearOfRewards_UnstakeAll() public {
        uint256 depositAmount = 100_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 10_000 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log18("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
    }

    function test_Bootstrapping_SmallStake_Late_LargeValidator_OneYearOfRewards_UnstakeAll() public {
        uint256 depositAmount = 100_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 100 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log18("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
    }

    // Test cases of turning a solo staker into a staking pool start here

    function test_Transforming_LargeStake_Late_SmallValidator_OneYearOfRewards_UnstakeAll() public {
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 10_000 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log18("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Transforming);
        run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
    } 

    function test_Transforming_SmallStake_Late_SmallValidator_OneYearOfRewards_UnstakeAll() public {
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 100 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log18("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Transforming);
        run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
    } 

    function test_Transforming_LargeStake_Late_LargeValidator_OneYearOfRewards_UnstakeAll() public {
        uint256 depositAmount = 100_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 10_000 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log18("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Transforming);
        run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
    }

    function test_Transforming_SmallStake_Late_LargeValidator_OneYearOfRewards_UnstakeAll() public {
        uint256 depositAmount = 100_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 100 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log18("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Transforming);
        run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
    }

    // Test cases of staking first and depositing later start here

    function test_Fundraising_SmallStake_Late_SmallValidator_OneYearOfRewards_UnstakeAll() public {
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 100 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log18("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Fundraising);
        run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
    }

    function test_Fundraising_LargeStake_Late_LargeValidator_OneYearOfRewards_UnstakeAll() public {
        uint256 depositAmount = 100_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 10_000 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log18("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Fundraising);
        run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
    }

    function test_Fundraising_SmallStake_Late_LargeValidator_OneYearOfRewards_UnstakeAll() public {
        uint256 depositAmount = 100_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 100 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log18("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Fundraising);
        run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
    }

    function test_Fundraising_LargeStake_Late_SmallValidator_OneYearOfRewards_UnstakeAll() public {
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 10_000 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log18("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Fundraising);
        run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
    }

    // Test cases of early staking start here

    function test_Bootstrapping_LargeStake_Early_SmallValidator_OneYearOfRewards_UnstakeAll() public {
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 10_000 ether;
        uint256 rewardsBeforeStaking = 1 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log18("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
    }

    function test_Bootstrapping_SmallStake_Early_SmallValidator_OneYearOfRewards_UnstakeAll() public {
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 100 ether;
        uint256 rewardsBeforeStaking = 1 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log18("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
    } 

    function test_Bootstrapping_LargeStake_Early_LargeValidator_OneYearOfRewards_UnstakeAll() public {
        uint256 depositAmount = 100_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 10_000 ether;
        uint256 rewardsBeforeStaking = 1 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log18("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
    }

    function test_Bootstrapping_SmallStake_Early_LargeValidator_OneYearOfRewards_UnstakeAll() public {
        uint256 depositAmount = 100_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 100 ether;
        uint256 rewardsBeforeStaking = 1 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log18("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
    } 

    // Test cases of no rewards start here

    function test_Bootstrapping_LargeStake_Late_NoRewards_UnstakeAll() public {
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 10_000 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log18("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
    }

    function test_Bootstrapping_LargeStake_Early_NoRewards_UnstakeAll() public {
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 10_000 ether;
        uint256 rewardsBeforeStaking = 1 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log18("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
    }

    function test_Transforming_LargeStake_Late_NoRewards_UnstakeAll() public {
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 10_000 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log18("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Transforming);
        run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
    }

    function test_Transforming_LargeStake_Early_NoRewards_UnstakeAll() public {
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 10_000 ether;
        uint256 rewardsBeforeStaking = 1 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log18("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Transforming);
        run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
    }

    function test_Fundraising_LargeStake_Late_NoRewards_UnstakeAll() public {
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 10_000 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log18("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Fundraising);
        run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
    }

    function test_Fundraising_LargeStake_Early_NoRewards_UnstakeAll() public {
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 10_000 ether;
        uint256 rewardsBeforeStaking = 1 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log18("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Fundraising);
        run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
    }

    // Test cases comparing two pools start here

    function test_Bootstrapping_Compare1Vs3Validators() public {
        uint256 depositAmount = 90_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 100 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log18("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        (, , , , , , , , uint256 lstPrice1, , , , , , , ) = run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
        Console.log("====================================================================");
        // delegation and lst point to the last element of delegations and lsts by default
        delegation = delegations[0];
        lst = lsts[0];
        depositAmount = 30_000_000 ether;
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        joinPool(BaseDelegation(delegation), depositAmount, makeAddr("2"), 2);
        joinPool(BaseDelegation(delegation), depositAmount, makeAddr("3"), 3);
        (, , , , , , , , uint256 lstPrice2, , , , , , , ) = run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * 3 * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
        assertApproxEqAbs(lstPrice1, lstPrice2, 1e11, "LST price mismatch");
    }     

    function test_Bootstrapping_Fundraising_CompareDepositModes() public {
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 100 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log18("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        (, , , , , , , , uint256 lstPrice1, , , , , , , ) = run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
        Console.log("====================================================================");
        // delegation and lst point to the last element of delegations and lsts by default
        delegation = delegations[0];
        lst = lsts[0];
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Fundraising);
        (, , , , , , , , uint256 lstPrice2, , , , , , , ) = run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
        assertEq(lstPrice1, lstPrice2, "LST price mismatch");
    }

    function test_Bootstrapping_Transforming_CompareDepositModes() public {
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 100 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log18("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        (, , , , , , , , uint256 lstPrice1, , , , , , , ) = run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
        Console.log("====================================================================");
        // delegation and lst point to the last element of delegations and lsts by default
        delegation = delegations[0];
        lst = lsts[0];
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Transforming);
        (, , , , , , , , uint256 lstPrice2, , , , , , , ) = run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
        assertEq(lstPrice1, lstPrice2, "LST price mismatch");
    }

    function test_Bootstrapping_CompareOneVsMoreDelegations() public {
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 100 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether / uint256(60) * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log18("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        (, , , , , , , , , , , , , , uint256 unstakedAmount1, ) = run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            9, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 51_000 ether / uint256(60) * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
        Console.log("====================================================================");
        // delegation and lst point to the last element of delegations and lsts by default
        delegation = delegations[0];
        lst = lsts[0];
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        (, , , , , , , , , , , , , , uint256 unstakedAmount2, ) = run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            9 * delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 51_000 ether / uint256(60) * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
        assertApproxEqAbs(unstakedAmount1, unstakedAmount2, 10, "unstaked amount not approximately same");
    }

    function test_Bootstrapping_CompareJoin2ndAndLeave2nd() public {
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 100 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether / uint256(60) * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log18("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        (, , , , , , , , uint256 lstPrice1, , , , , , uint256 unstakedAmount1, ) = run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 51_000 ether / uint256(60) * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
        Console.log("====================================================================");
        // delegation and lst point to the last element of delegations and lsts by default
        delegation = delegations[0];
        lst = lsts[0];
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        joinPool(BaseDelegation(delegation), depositAmount, makeAddr("2"), 2);
        vm.startPrank(makeAddr("2"));
        delegation.leavePool(validator(2));
        vm.stopPrank();
        (, , , , , , , , uint256 lstPrice2, , , , , , uint256 unstakedAmount2, ) = run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 51_000 ether / uint256(60) * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
        assertEq(lstPrice1, lstPrice2, "LST price mismatch");
        assertEq(unstakedAmount1, unstakedAmount2, "unstaked amount mismatch");
    }

    function test_Bootstrapping_CompareJoin2ndAndLeave1st() public {
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 100 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether / uint256(60) * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log18("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        (, , , , , , , , uint256 lstPrice1, , , , , , uint256 unstakedAmount1, ) = run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 51_000 ether / uint256(60) * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
        Console.log("====================================================================");
        // delegation and lst point to the last element of delegations and lsts by default
        delegation = delegations[0];
        lst = lsts[0];
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        joinPool(BaseDelegation(delegation), depositAmount, makeAddr("2"), 2);
        vm.startPrank(owner);
        delegation.leavePool(validator(1));
        vm.stopPrank();
        (, , , , , , , , uint256 lstPrice2, , , , , , uint256 unstakedAmount2, ) = run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 51_000 ether / uint256(60) * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
        assertEq(lstPrice1, lstPrice2, "LST price mismatch");
        assertEq(unstakedAmount1, unstakedAmount2, "unstaked amount mismatch");
    }

    function test_Bootstrapping_CompareJoin3MoreAndLeave3() public {
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 100 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether / uint256(60) * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log18("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        addValidator(BaseDelegation(delegation), 2 * depositAmount, DepositMode.Bootstrapping);
        (, , , , , , , , uint256 lstPrice1, , , , , , uint256 unstakedAmount1, ) = run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 51_000 ether / uint256(60) * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
        Console.log("====================================================================");
        // delegation and lst point to the last element of delegations and lsts by default
        delegation = delegations[0];
        lst = lsts[0];
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        joinPool(BaseDelegation(delegation), 4 * depositAmount, makeAddr("2"), 2);
        joinPool(BaseDelegation(delegation), 2 * depositAmount, makeAddr("3"), 3);
        joinPool(BaseDelegation(delegation), 5 * depositAmount, makeAddr("4"), 4);
        vm.startPrank(makeAddr("2"));
        delegation.leavePool(validator(2));
        vm.stopPrank();
        vm.startPrank(owner);
        delegation.leavePool(validator(1));
        vm.stopPrank();
        vm.startPrank(makeAddr("4"));
        delegation.leavePool(validator(4));
        vm.stopPrank();
        assertEq(delegation.validators().length, 1, "validators did not leavePool(");
        (, , , , , , , , uint256 lstPrice2, , , , , , uint256 unstakedAmount2, ) = run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 51_000 ether / uint256(60) * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
        assertEq(lstPrice1, lstPrice2, "LST price mismatch");
        assertEq(unstakedAmount1, unstakedAmount2, "unstaked amount mismatch");
    }

    // Additional test cases start here

    function test_LeaveAfterOthersStakedPendingWithdrawalsDepositReduction() public {
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 100 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether / uint256(60) * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log18("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        (, , , , , , , , uint256 lstPrice1, , , , , , uint256 unstakedAmount1, ) = run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 51_000 ether / uint256(60) * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
        joinPool(BaseDelegation(delegation), depositAmount, makeAddr("2"), 2);
        (, , , , , , , , uint256 lstPrice2, , , , , , uint256 unstakedAmount2, ) = run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 51_000 ether / uint256(60) * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
        address staker = stakers[4-1];
        // stake and unstake to make pendingWithdrawals > 0 before leaving is initiated
        vm.startPrank(staker);
        uint256 lstBalance = lst.balanceOf(staker);
        vm.deal(staker, staker.balance + 10_000 ether);
        delegation.stake{value: 10_000 ether}();
        delegation.unstake(lst.balanceOf(staker) - lstBalance);
        vm.stopPrank();
        // initiate leaving but it can't be completed because of pending withdrawals
        vm.startPrank(makeAddr("2"));
        assertTrue(delegation.pendingWithdrawals(validator(2)), "there should be pending withdrawals");
        delegation.leavePool(validator(2));
        assertTrue(delegation.pendingWithdrawals(validator(2)), "there should be pending withdrawals");
        vm.stopPrank();
        // if staker claims which calls withdrawDeposit() before the unbonding period, pendingWithdrawals will not be 0
        vm.startPrank(staker);
        delegation.claim();
        assertTrue(delegation.pendingWithdrawals(validator(2)), "there should be pending withdrawals");
        vm.roll(block.number + delegation.unbondingPeriod());
        vm.stopPrank();
        // stake and unstake but pendingWithdrawals remains 0 after leaving was initiated
        vm.startPrank(staker);
        lstBalance = lst.balanceOf(staker);
        vm.deal(staker, staker.balance + 10_000 ether);
        delegation.stake{value: 10_000 ether}();
        delegation.unstake(lst.balanceOf(staker) - lstBalance);
        vm.stopPrank();
        // if staker claims which calls withdrawDeposit() after the unbonding period, pendingWithdrawals will be 0
        vm.startPrank(staker);
        delegation.claim();
        assertFalse(delegation.pendingWithdrawals(validator(2)), "there should not be pending withdrawals");
        vm.stopPrank();
        // initiate leaving again, the validator's deposit gets decreased
        vm.startPrank(makeAddr("2"));
        delegation.leavePool(validator(2));
        // if staker unstakes after the validator requested leaving, the validator's pendingWithdrawals remain 0
        vm.stopPrank();
        lstBalance = lst.balanceOf(staker);
        vm.deal(staker, staker.balance + 10_000 ether);
        vm.startPrank(staker);
        delegation.stake{value: 10_000 ether}();
        delegation.unstake(lst.balanceOf(staker) - lstBalance);
        vm.stopPrank();
        assertFalse(delegation.pendingWithdrawals(validator(2)), "there should not be pending withdrawals");
        vm.startPrank(makeAddr("2"));
        // completion of leaving has to wait for the unbonding period
        delegation.completeLeaving(validator(2));
        assertEq(delegation.validators().length, 2, "validator leaving should not be completed yet");
        vm.roll(block.number + delegation.unbondingPeriod());
        // if staker claimes before the validator's control address completes leaving, the validator's deposit is not withdrawn
        vm.stopPrank();
        vm.startPrank(staker);
        delegation.claim();
        vm.stopPrank();
        vm.startPrank(makeAddr("2"));
        // completion of leaving is finally possible 
        delegation.completeLeaving(validator(2));
        assertEq(delegation.validators().length, 1, "validator leaving should be completed");
        vm.stopPrank();
        assertLt(lstPrice1, lstPrice2, "LST price should increase");
        assertGt(unstakedAmount1, unstakedAmount2, "unstaked amount should decrease");
    }

    function test_LeaveAfterOthersStakedNoPendingWithdrawalsDepositReduction() public {
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 100 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether / uint256(60) * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log18("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        (, , , , , , , , uint256 lstPrice1, , , , , , uint256 unstakedAmount1, ) = run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 51_000 ether / uint256(60) * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
        joinPool(BaseDelegation(delegation), depositAmount, makeAddr("2"), 2);
        (, , , , , , , , uint256 lstPrice2, , , , , , uint256 unstakedAmount2, ) = run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 51_000 ether / uint256(60) * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
        vm.roll(block.number + delegation.unbondingPeriod());
        address staker = stakers[4-1];
        // if staker claims which calls withdrawDeposit() after the unbonding period, pendingWithdrawals will be 0
        vm.startPrank(staker);
        delegation.claim();
        assertFalse(delegation.pendingWithdrawals(validator(2)), "there should not be pending withdrawals");
        vm.stopPrank();
        // initiate leaving, the validator's deposit gets decreased
        vm.startPrank(makeAddr("2"));
        delegation.leavePool(validator(2));
        // if staker unstakes after the validator requested leaving, the validator's pendingWithdrawals remain 0
        vm.stopPrank();
        uint256 lstBalance = lst.balanceOf(staker);
        vm.deal(staker, staker.balance + 10_000 ether);
        vm.startPrank(staker);
        delegation.stake{value: 10_000 ether}();
        delegation.unstake(lst.balanceOf(staker) - lstBalance);
        vm.stopPrank();
        assertFalse(delegation.pendingWithdrawals(validator(2)), "there should not be pending withdrawals");
        vm.startPrank(makeAddr("2"));
        // completion of leaving has to wait for the unbonding period
        delegation.completeLeaving(validator(2));
        assertEq(delegation.validators().length, 2, "validator leaving should not be completed yet");
        vm.roll(block.number + delegation.unbondingPeriod());
        // if staker claimes before the validator's control address completes leaving, the validator's deposit is not withdrawn
        vm.stopPrank();
        vm.startPrank(staker);
        delegation.claim();
        vm.stopPrank();
        vm.startPrank(makeAddr("2"));
        // completion of leaving is finally possible 
        delegation.completeLeaving(validator(2));
        assertEq(delegation.validators().length, 1, "validator leaving should be completed");
        vm.stopPrank();
        assertLt(lstPrice1, lstPrice2, "LST price should increase");
        assertGt(unstakedAmount1, unstakedAmount2, "unstaked amount should decrease");
    }

    function test_LeaveAfterOthersStakedPendingWithdrawalsRefund() public {
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 100 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether / uint256(60) * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log18("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        (, , , , , , , , uint256 lstPrice1, , , , , , uint256 unstakedAmount1, ) = run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 51_000 ether / uint256(60) * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
        joinPool(BaseDelegation(delegation), depositAmount, makeAddr("2"), 2);
        (, , , , , , , , uint256 lstPrice2, , , , , , uint256 unstakedAmount2, ) = run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 51_000 ether / uint256(60) * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
        address staker = stakers[4-1];
        // stake and unstake to make pendingWithdrawals > 0 before leaving is initiated
        vm.startPrank(staker);
        uint256 lstBalance = lst.balanceOf(staker);
        vm.deal(staker, staker.balance + 10_000 ether);
        delegation.stake{value: 10_000 ether}();
        delegation.unstake(lst.balanceOf(staker) - lstBalance);
        vm.stopPrank();
        // initiate leaving but it can't be completed because of pending withdrawals
        vm.startPrank(makeAddr("2"));
        assertTrue(delegation.pendingWithdrawals(validator(2)), "there should be pending withdrawals");
        delegation.leavePool(validator(2));
        assertTrue(delegation.pendingWithdrawals(validator(2)), "there should be pending withdrawals");
        vm.stopPrank();
        // if staker claims which calls withdrawDeposit() before the unbonding period, pendingWithdrawals will not be 0
        vm.startPrank(staker);
        delegation.claim();
        assertTrue(delegation.pendingWithdrawals(validator(2)), "there should be pending withdrawals");
        vm.roll(block.number + delegation.unbondingPeriod());
        vm.stopPrank();
        // stake and unstake but pendingWithdrawals remains 0 after leaving was initiated
        vm.startPrank(staker);
        lstBalance = lst.balanceOf(staker);
        vm.deal(staker, staker.balance + 10_000 ether);
        delegation.stake{value: 10_000 ether}();
        delegation.unstake(lst.balanceOf(staker) - lstBalance);
        vm.stopPrank();
        // control address buys LST to match the validator's deposit
        uint256 price = delegation.getPrice();
        uint256 amount = (delegation.getDeposit(validator(2)) * 1 ether - lst.balanceOf(makeAddr("2")) * price) / price;
        uint256 unstaked = (delegation.getStake() + delegation.getTaxedRewards()) * (amount + lst.balanceOf(makeAddr("2"))) / lst.totalSupply();
        uint256 refund = unstaked - delegation.getDeposit(validator(2)) + 0;
        vm.startPrank(owner);
        lst.transfer(makeAddr("2"), amount);
        vm.stopPrank();
        // if staker claims which calls withdrawDeposit() after the unbonding period, pendingWithdrawals will be 0
        vm.startPrank(staker);
        delegation.claim();
        assertFalse(delegation.pendingWithdrawals(validator(2)), "there should not be pending withdrawals");
        vm.stopPrank();
        // initiate leaving again, it gets completed instantly, the surplus gets unstaked and can be claimed
        vm.startPrank(makeAddr("2"));
        delegation.leavePool(validator(2));
        assertEq(delegation.validators().length, 1, "validator leaving should be completed");
        // control address can't claim the refund before the unbonding period
        uint256 controlAddressBalance = makeAddr("2").balance;
        delegation.claim();
        assertEq(makeAddr("2").balance - controlAddressBalance, 0, "control address should not be able to claim refund");
        vm.roll(block.number + delegation.unbondingPeriod());
        // control address can claim the refund after the unbonding period 
        controlAddressBalance = makeAddr("2").balance;
        delegation.claim();
        assertEq(makeAddr("2").balance - controlAddressBalance, refund, "control address should be able to claim refund");
        vm.stopPrank();
        assertLt(lstPrice1, lstPrice2, "LST price should increase");
        assertGt(unstakedAmount1, unstakedAmount2, "unstaked amount should decrease");
    }

    function test_LeaveAfterOthersStakedNoPendingWithdrawalsRefund() public {
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 100 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether / uint256(60) * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log18("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        (, , , , , , , , uint256 lstPrice1, , , , , , uint256 unstakedAmount1, ) = run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 51_000 ether / uint256(60) * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
        joinPool(BaseDelegation(delegation), depositAmount, makeAddr("2"), 2);
        (, , , , , , , , uint256 lstPrice2, , , , , , uint256 unstakedAmount2, ) = run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 51_000 ether / uint256(60) * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
        address staker = stakers[4-1];
        // control address buys LST to match the validator's deposit
        uint256 price = delegation.getPrice();
        uint256 amount = (delegation.getDeposit(validator(2)) * 1 ether - lst.balanceOf(makeAddr("2")) * price) / price;
        uint256 unstaked = (delegation.getStake() + delegation.getTaxedRewards()) * (amount + lst.balanceOf(makeAddr("2"))) / lst.totalSupply();
        uint256 refund = unstaked - delegation.getDeposit(validator(2));
        vm.startPrank(owner);
        lst.transfer(makeAddr("2"), amount);
        vm.stopPrank();
        vm.roll(block.number + delegation.unbondingPeriod());
        // if staker claims which calls withdrawDeposit() after the unbonding period, pendingWithdrawals will be 0
        vm.startPrank(staker);
        delegation.claim();
        assertFalse(delegation.pendingWithdrawals(validator(2)), "there should not be pending withdrawals");
        vm.stopPrank();
        // initiate leaving again, it gets completed instantly, the surplus gets unstaked and can be claimed
        vm.startPrank(makeAddr("2"));
        delegation.leavePool(validator(2));
        assertEq(delegation.validators().length, 1, "validator leaving should be completed");
        // control address can't claim the refund before the unbonding period
        uint256 controlAddressBalance = makeAddr("2").balance;
        delegation.claim();
        assertEq(makeAddr("2").balance - controlAddressBalance, 0, "control address should not be able to claim refund");
        vm.roll(block.number + delegation.unbondingPeriod());
        // control address can claim the refund after the unbonding period 
        controlAddressBalance = makeAddr("2").balance;
        delegation.claim();
        assertEq(makeAddr("2").balance - controlAddressBalance, refund, "control address should be able to claim refund");
        vm.stopPrank();
        assertLt(lstPrice1, lstPrice2, "LST price should increase");
        assertGt(unstakedAmount1, unstakedAmount2, "unstaked amount should decrease");
    }

    function test_LeaveAfterOthersStakedPendingWithdrawalsNoRefund() public {
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 100 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether / uint256(60) * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log18("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        (, , , , , , , , uint256 lstPrice1, , , , , , uint256 unstakedAmount1, ) = run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 51_000 ether / uint256(60) * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
        joinPool(BaseDelegation(delegation), depositAmount, makeAddr("2"), 2);
        (, , , , , , , , uint256 lstPrice2, , , , , , uint256 unstakedAmount2, ) = run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 51_000 ether / uint256(60) * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
        address staker = stakers[4-1];
        // stake and unstake to make pendingWithdrawals > 0 before leaving is initiated
        vm.startPrank(staker);
        uint256 lstBalance = lst.balanceOf(staker);
        vm.deal(staker, staker.balance + 10_000 ether);
        delegation.stake{value: 10_000 ether}();
        delegation.unstake(lst.balanceOf(staker) - lstBalance);
        vm.stopPrank();
        // initiate leaving but it can't be completed because of pending withdrawals
        vm.startPrank(makeAddr("2"));
        assertTrue(delegation.pendingWithdrawals(validator(2)), "there should be pending withdrawals");
        delegation.leavePool(validator(2));
        assertTrue(delegation.pendingWithdrawals(validator(2)), "there should be pending withdrawals");
        vm.stopPrank();
        // if staker claims which calls withdrawDeposit() before the unbonding period, pendingWithdrawals will not be 0
        vm.startPrank(staker);
        delegation.claim();
        assertTrue(delegation.pendingWithdrawals(validator(2)), "there should be pending withdrawals");
        vm.roll(block.number + delegation.unbondingPeriod());
        vm.stopPrank();
        // stake and unstake but pendingWithdrawals remains 0 after leaving was initiated
        vm.startPrank(staker);
        lstBalance = lst.balanceOf(staker);
        vm.deal(staker, staker.balance + 10_000 ether);
        delegation.stake{value: 10_000 ether}();
        delegation.unstake(lst.balanceOf(staker) - lstBalance);
        vm.stopPrank();
        // control address buys LST to match the validator's deposit
        uint256 price = delegation.getPrice();
        uint256 amount = (delegation.getDeposit(validator(2)) * 1 ether - lst.balanceOf(makeAddr("2")) * price) / price;
        uint256 unstaked = (delegation.getStake() + delegation.getTaxedRewards()) * (amount + lst.balanceOf(makeAddr("2"))) / lst.totalSupply();
        uint256 refund = unstaked - delegation.getDeposit(validator(2)) + 0;
        amount = (delegation.getDeposit(validator(2)) * 1 ether - refund * 1 ether - lst.balanceOf(makeAddr("2")) * price) / price;
        vm.startPrank(owner);
        lst.transfer(makeAddr("2"), amount);
        vm.stopPrank();
        // if staker claims which calls withdrawDeposit() after the unbonding period, pendingWithdrawals will be 0
        vm.startPrank(staker);
        delegation.claim();
        assertFalse(delegation.pendingWithdrawals(validator(2)), "there should not be pending withdrawals");
        vm.stopPrank();
        // initiate leaving again, it gets completed instantly, the surplus gets unstaked and can be claimed
        vm.startPrank(makeAddr("2"));
        delegation.leavePool(validator(2));
        assertEq(delegation.validators().length, 1, "validator leaving should be completed");
        vm.roll(block.number + delegation.unbondingPeriod());
        // there is no refund to claim after the unbonding period 
        uint256 controlAddressBalance = makeAddr("2").balance;
        delegation.claim();
        assertEq(makeAddr("2").balance - controlAddressBalance, 0, "there should be no refund");
        vm.stopPrank();
        assertLt(lstPrice1, lstPrice2, "LST price should increase");
        assertGt(unstakedAmount1, unstakedAmount2, "unstaked amount should decrease");
    }

    function test_LeaveAfterOthersStakedNoPendingWithdrawalsNoRefund() public {
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 100 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether / uint256(60) * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log18("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        (, , , , , , , , uint256 lstPrice1, , , , , , uint256 unstakedAmount1, ) = run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 51_000 ether / uint256(60) * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
        joinPool(BaseDelegation(delegation), depositAmount, makeAddr("2"), 2);
        (, , , , , , , , uint256 lstPrice2, , , , , , uint256 unstakedAmount2, ) = run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 51_000 ether / uint256(60) * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
        address staker = stakers[4-1];
        // control address buys LST to match the validator's deposit
        uint256 price = delegation.getPrice();
        uint256 amount = (delegation.getDeposit(validator(2)) * 1 ether - lst.balanceOf(makeAddr("2")) * price) / price;
        uint256 unstaked = (delegation.getStake() + delegation.getTaxedRewards()) * (amount + lst.balanceOf(makeAddr("2"))) / lst.totalSupply();
        uint256 refund = unstaked - delegation.getDeposit(validator(2)) + 1;
        amount = (delegation.getDeposit(validator(2)) * 1 ether - refund * 1 ether - lst.balanceOf(makeAddr("2")) * price) / price;
        vm.startPrank(owner);
        lst.transfer(makeAddr("2"), amount);
        vm.stopPrank();
        vm.roll(block.number + delegation.unbondingPeriod());
        // if staker claims which calls withdrawDeposit() after the unbonding period, pendingWithdrawals will be 0
        vm.startPrank(staker);
        delegation.claim();
        assertFalse(delegation.pendingWithdrawals(validator(2)), "there should not be pending withdrawals");
        vm.stopPrank();
        // initiate leaving, it gets completed instantly, the surplus gets unstaked and can be claimed
        vm.startPrank(makeAddr("2"));
        delegation.leavePool(validator(2));
        assertEq(delegation.validators().length, 1, "validator leaving should be completed");
        vm.roll(block.number + delegation.unbondingPeriod());
        // there is no refund to claim after the unbonding period 
        uint256 controlAddressBalance = makeAddr("2").balance;
        delegation.claim();
        assertEq(makeAddr("2").balance - controlAddressBalance, 0, "there should be no refund");
        vm.stopPrank();
        assertLt(lstPrice1, lstPrice2, "LST price should increase");
        assertGt(unstakedAmount1, unstakedAmount2, "unstaked amount should decrease");
    }

    function test_DepositMultipleValidatorsFromPool() public {
        uint256 depositAmount = 10_000_000 ether;
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Fundraising);
        vm.deal(stakers[0], stakers[0].balance + 200 ether);
        vm.startPrank(stakers[0]);
        delegation.stake{value: 100 ether}();
        uint256 stakerBalance = stakers[0].balance;
        delegation.unstake(lst.balanceOf(stakers[0]));
        vm.roll(block.number + delegation.unbondingPeriod());
        delegation.claim();
        assertEq(stakers[0].balance - stakerBalance, 100 ether, "balance mismatch after claiming");
        vm.stopPrank();
        depositFromPool(BaseDelegation(delegation), depositAmount, 2);
        vm.startPrank(stakers[0]);
        delegation.stake{value: 100 ether}();
        stakerBalance = stakers[0].balance;
        delegation.unstake(lst.balanceOf(stakers[0]));
        vm.roll(block.number + delegation.unbondingPeriod());
        delegation.claim();
        assertEq(stakers[0].balance - stakerBalance, 100 ether, "balance mismatch after claiming");
        vm.stopPrank();
    }

    function test_InstantUnstakeBeforeActivation() public {
        vm.deal(stakers[0], stakers[0].balance + 100 ether);
        vm.startPrank(stakers[0]);
        delegation.stake{value: 100 ether}();
        uint256 stakerBalance = stakers[0].balance;
        delegation.unstake(lst.balanceOf(stakers[0]));
        delegation.claim();
        assertEq(stakers[0].balance - stakerBalance, 100 ether, "balance must increase instantly");
        vm.stopPrank();
    }

    function test_JoinDuringFundraising() public {
        uint256 depositAmount = 10_000_000 ether;
        vm.deal(stakers[0], stakers[0].balance + 1000 ether);
        vm.startPrank(stakers[0]);
        delegation.stake{value: 1000 ether}();
        vm.stopPrank();
        joinPool(BaseDelegation(delegation), depositAmount, makeAddr("2"), 2);
        assertEq(delegation.getDeposit(validator(2)), depositAmount + 1000 ether, "Incorrect validator deposit");
    }

    function beforeTestSetup(bytes4 testSelector) public pure returns (bytes[] memory beforeTestCalldata) {
        if (
            testSelector == this.test_UseStakeForFirstJoinerAfterAllValidatorsLeft.selector ||
            testSelector == this.test_UseStakeForNewDepositAfterAllValidatorsLeft.selector
        ) {
            beforeTestCalldata = new bytes[](1);
            beforeTestCalldata[0] = abi.encodePacked(this.test_StakeRemainingAfterAllValidatorsLeft.selector);
        }
    }

    function test_UseStakeForFirstJoinerAfterAllValidatorsLeft() public {
        uint256 depositAmount = 10_000_000 ether;
        vm.deal(stakers[0], stakers[0].balance + 1000 ether);
        vm.startPrank(stakers[0]);
        delegation.stake{value: 1000 ether}();
        vm.stopPrank();
        joinPool(BaseDelegation(delegation), depositAmount, makeAddr("5"), 5);
        assertEq(delegation.getDeposit(validator(5)), depositAmount + 1100 ether, "Incorrect validator deposit");
    }

    function test_UseStakeForNewDepositAfterAllValidatorsLeft() public {
        uint256 depositAmount = 9_998_900 ether;
        vm.deal(stakers[0], stakers[0].balance + 1000 ether);
        vm.startPrank(stakers[0]);
        delegation.stake{value: 1000 ether}();
        vm.stopPrank();
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
    }

    function test_StakeRemainingAfterAllValidatorsLeft() public {
        uint256 depositAmount = 10_000_000 ether;
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        joinPool(BaseDelegation(delegation), depositAmount, makeAddr("2"), 2);
        joinPool(BaseDelegation(delegation), depositAmount, makeAddr("3"), 3);
        joinPool(BaseDelegation(delegation), depositAmount, makeAddr("4"), 4);
        vm.deal(stakers[0], stakers[0].balance + 100 ether);
        uint256 totalStaked = delegation.getStake();
        assertEq(totalStaked, 4 * depositAmount, "Incorrect total stake");
        vm.startPrank(stakers[0]);
        delegation.stake{value: 100 ether}();
        vm.stopPrank();
        totalStaked = delegation.getStake();
        assertEq(totalStaked, 4 * depositAmount + 100 ether, "Incorrect total stake");
        vm.startPrank(makeAddr("2"));
        delegation.leavePool(validator(2));
        vm.stopPrank();
        totalStaked = delegation.getStake();
        assertEq(totalStaked, 3 * depositAmount + 100 ether, "Incorrect total stake");
        vm.startPrank(owner);
        delegation.leavePool(validator(1));
        vm.stopPrank();
        totalStaked = delegation.getStake();
        assertEq(totalStaked, 2 * depositAmount + 100 ether, "Incorrect total stake");
        vm.startPrank(makeAddr("4"));
        delegation.leavePool(validator(4));
        vm.stopPrank();
        totalStaked = delegation.getStake();
        assertEq(totalStaked, 1 * depositAmount + 100 ether, "Incorrect total stake");
        vm.roll(block.number + delegation.unbondingPeriod());
        totalStaked = delegation.getStake();
        assertEq(totalStaked, 1 * depositAmount + 100 ether, "Incorrect total stake");
        vm.startPrank(makeAddr("2"));
        delegation.completeLeaving(validator(2));
        vm.stopPrank();
        totalStaked = delegation.getStake();
        assertEq(totalStaked, 1 * depositAmount + 100 ether, "Incorrect total stake");
        vm.startPrank(makeAddr("3"));
        delegation.leavePool(validator(3));
        vm.stopPrank();
        totalStaked = delegation.getStake();
        assertEq(totalStaked, 100 ether, "Incorrect total stake");
        vm.roll(block.number + delegation.unbondingPeriod());
        totalStaked = delegation.getStake();
        assertEq(totalStaked, 100 ether, "Incorrect total stake");
        vm.startPrank(owner);
        delegation.completeLeaving(validator(1));
        vm.stopPrank();
        totalStaked = delegation.getStake();
        assertEq(totalStaked, 100 ether, "Incorrect total stake");
        vm.startPrank(makeAddr("4"));
        delegation.completeLeaving(validator(4));
        vm.stopPrank();
        totalStaked = delegation.getStake();
        assertEq(totalStaked, 100 ether, "Incorrect total stake");
        vm.startPrank(makeAddr("3"));
        delegation.completeLeaving(validator(3));
        vm.stopPrank();
        totalStaked = delegation.getStake();
        assertEq(totalStaked, 100 ether, "Incorrect total stake");
    }

    function test_LargeUnstakeUndepositValidators() public {
        uint256 depositAmount = 10_000_000 ether;
        addValidator(BaseDelegation(delegation), 2 * depositAmount, DepositMode.Bootstrapping);
        joinPool(BaseDelegation(delegation), 2 * depositAmount, makeAddr("2"), 2);
        joinPool(BaseDelegation(delegation), 2 * depositAmount, makeAddr("3"), 3);
        joinPool(BaseDelegation(delegation), 2 * depositAmount, makeAddr("4"), 4);
        joinPool(BaseDelegation(delegation), 2 * depositAmount, makeAddr("5"), 5);
        vm.startPrank(makeAddr("5"));
        delegation.leavePool(validator(5));
        vm.stopPrank();
        assertEq(delegation.getStake(), 80 * depositAmount / 10, "incorrect stake");
        assertEq(delegation.validators().length, 4, "incorrect number of validators");
        assertEq(delegation.getDeposit(validator(1)), 20 * depositAmount / 10, "validator deposits are decreased equally");
        assertEq(delegation.getDeposit(validator(2)), 20 * depositAmount / 10, "validator deposits are decreased equally");
        assertEq(delegation.getDeposit(validator(3)), 20 * depositAmount / 10, "validator deposits are decreased equally");
        assertEq(delegation.getDeposit(validator(4)), 20 * depositAmount / 10, "validator deposits are decreased equally");
        vm.startPrank(makeAddr("2"));
        delegation.unstake(lst.balanceOf(makeAddr("2")));
        assertEq(delegation.getDeposit(validator(1)), 15 * depositAmount / 10, "validator deposits are decreased equally");
        assertEq(delegation.getDeposit(validator(2)), 15 * depositAmount / 10, "validator deposits are decreased equally");
        assertEq(delegation.getDeposit(validator(3)), 15 * depositAmount / 10, "validator deposits are decreased equally");
        assertEq(delegation.getDeposit(validator(4)), 15 * depositAmount / 10, "validator deposits are decreased equally");
        vm.roll(block.number + delegation.unbondingPeriod());
        uint256 balanceBefore = makeAddr("2").balance;
        delegation.claim();
        assertEq(makeAddr("2").balance - balanceBefore, 2 * depositAmount, "unstaked vs claimed amount mismatch");
        assertEq(delegation.getStake(), 60 * depositAmount / 10, "incorrect stake");
        assertEq(delegation.validators().length, 4, "incorrect number of validators");
        vm.stopPrank();
        vm.startPrank(makeAddr("3"));
        delegation.unstake(lst.balanceOf(makeAddr("3")));
        assertEq(delegation.getDeposit(validator(1)), 10 * depositAmount / 10, "validator deposits are decreased equally");
        assertEq(delegation.getDeposit(validator(2)), 10 * depositAmount / 10, "validator deposits are decreased equally");
        assertEq(delegation.getDeposit(validator(3)), 10 * depositAmount / 10, "validator deposits are decreased equally");
        assertEq(delegation.getDeposit(validator(4)), 10 * depositAmount / 10, "validator deposits are decreased equally");
        vm.roll(block.number + delegation.unbondingPeriod());
        balanceBefore = makeAddr("3").balance;
        delegation.claim();
        assertEq(makeAddr("3").balance - balanceBefore, 2 * depositAmount, "unstaked vs claimed amount mismatch");
        assertEq(delegation.getStake(), 40 * depositAmount / 10, "incorrect stake");
        assertEq(delegation.validators().length, 4, "incorrect number of validators");
        vm.stopPrank();
        vm.startPrank(makeAddr("4"));
        delegation.unstake(15 * lst.balanceOf(makeAddr("4")) / 20);
        assertEq(delegation.getStake(), 25 * depositAmount / 10, "incorrect stake");
        assertEq(delegation.validators().length, 4, "incorrect number of validators");
        assertEq(delegation.getDeposit(validator(1)), 10 * depositAmount / 10, "validator deposit mismatch");
        assertEq(delegation.getDeposit(validator(2)), 10 * depositAmount / 10, "validator deposit mismatch");
        assertEq(delegation.getDeposit(validator(3)), 0, "validator deposit mismatch");
        assertEq(delegation.getDeposit(validator(4)), 0, "validator deposit mismatch");
        vm.roll(block.number + delegation.unbondingPeriod());
        balanceBefore = makeAddr("4").balance;
        delegation.claim();
        assertEq(makeAddr("4").balance - balanceBefore, 15 * depositAmount / 10, "unstaked vs claimed amount mismatch");
        assertEq(delegation.getStake(), 25 * depositAmount / 10, "incorrect stake");
        assertEq(delegation.validators().length, 2, "incorrect number of validators");
        assertEq(delegation.getDeposit(validator(1)), 125 * depositAmount / 100, "validator deposit mismatch");
        assertEq(delegation.getDeposit(validator(2)), 125 * depositAmount / 100, "validator deposit mismatch");
        assertEq(delegation.getDeposit(validator(3)), 0, "validator deposit mismatch");
        assertEq(delegation.getDeposit(validator(4)), 0, "validator deposit mismatch");
        vm.stopPrank();
        vm.startPrank(owner);
        delegation.unstake(lst.balanceOf(owner));
        assertEq(delegation.getStake(), 5 * depositAmount / 10, "incorrect stake");
        assertEq(delegation.validators().length, 2, "incorrect number of validators");
        assertEq(delegation.getDeposit(validator(1)), 0, "validator deposit mismatch");
        assertEq(delegation.getDeposit(validator(2)), 0, "validator deposit mismatch");
        assertEq(delegation.getDeposit(validator(3)), 0, "validator deposit mismatch");
        assertEq(delegation.getDeposit(validator(4)), 0, "validator deposit mismatch");
        vm.roll(block.number + delegation.unbondingPeriod());
        balanceBefore = owner.balance;
        delegation.claim();
        assertEq(owner.balance - balanceBefore, 20 * depositAmount / 10, "unstaked vs claimed amount mismatch");
        assertEq(delegation.getStake(), 5 * depositAmount / 10, "incorrect stake");
        assertEq(delegation.validators().length, 0, "incorrect number of validators");
        assertEq(delegation.getDeposit(validator(1)), 0, "validator deposit mismatch");
        assertEq(delegation.getDeposit(validator(2)), 0, "validator deposit mismatch");
        assertEq(delegation.getDeposit(validator(3)), 0, "validator deposit mismatch");
        assertEq(delegation.getDeposit(validator(4)), 0, "validator deposit mismatch");
        vm.stopPrank();
        vm.startPrank(makeAddr("4"));
        delegation.unstake(lst.balanceOf(makeAddr("4")));
        assertEq(delegation.getStake(), 0, "incorrect stake");
        assertEq(delegation.validators().length, 0, "incorrect number of validators");
        assertEq(delegation.getDeposit(validator(1)), 0, "validator deposit mismatch");
        assertEq(delegation.getDeposit(validator(2)), 0, "validator deposit mismatch");
        assertEq(delegation.getDeposit(validator(3)), 0, "validator deposit mismatch");
        assertEq(delegation.getDeposit(validator(4)), 0, "validator deposit mismatch");
        vm.roll(block.number + delegation.unbondingPeriod());
        balanceBefore = makeAddr("4").balance;
        delegation.claim();
        assertEq(makeAddr("4").balance - balanceBefore, 5 * depositAmount / 10, "unstaked vs claimed amount mismatch");
        assertEq(delegation.getStake(), 0, "incorrect stake");
        assertEq(delegation.validators().length, 0, "incorrect number of validators");
        assertEq(delegation.getDeposit(validator(1)), 0, "validator deposit mismatch");
        assertEq(delegation.getDeposit(validator(2)), 0, "validator deposit mismatch");
        assertEq(delegation.getDeposit(validator(3)), 0, "validator deposit mismatch");
        assertEq(delegation.getDeposit(validator(4)), 0, "validator deposit mismatch");
        vm.stopPrank();
    }

    function test_DepositTwice_Bootstrapping_Bootstrapping() public {
        uint256 depositAmount = 10_000_000 ether;
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
    }

    function test_DepositLeaveDeposit_Bootstrapping_Fundraising() public {
        uint256 depositAmount = 10_000_000 ether;
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        vm.startPrank(owner);
        delegation.leavePool(validator(1));
        vm.stopPrank();
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Fundraising);
    }

    function test_RevertWhen_DepositTwice_Bootstrapping_Fundraising() public {
        uint256 depositAmount = 10_000_000 ether;
        this.addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        vm.expectRevert(); //vm.expectPartialRevert(BaseDelegation.DepositContractCallFailed.selector);
        this.addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Fundraising);
    }

    function test_RevertWhen_DepositTwice_Fundraising_Fundraising() public {
        uint256 depositAmount = 10_000_000 ether;
        this.addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Fundraising);
        vm.expectRevert(); //vm.expectPartialRevert(BaseDelegation.DepositContractCallFailed.selector);
        this.addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Fundraising);
    }

    function test_DepositTwice_Fundraising_Bootstrapping() public {
        uint256 depositAmount = 10_000_000 ether;
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Fundraising);
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
    }

    function test_DepositTwice_Transforming_Bootstrapping() public {
        uint256 depositAmount = 10_000_000 ether;
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Transforming);
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
    }

    function test_DepositLeaveDeposit_Transforming_Fundraising() public {
        uint256 depositAmount = 10_000_000 ether;
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Transforming);
        vm.startPrank(owner);
        delegation.leavePool(validator(1));
        vm.stopPrank();
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Fundraising);
    }

    function test_RevertWhen_DepositTwice_Transforming_Fundraising() public {
        uint256 depositAmount = 10_000_000 ether;
        this.addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Transforming);
        vm.expectRevert(); //vm.expectPartialRevert(BaseDelegation.DepositContractCallFailed.selector);
        this.addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Fundraising);
    }

    function test_ManyVsOneStake_UnstakeAll() public {
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 110_000_000 ether;
        uint256 delegatedAmount = 10_000 ether;
        uint256 rewardsBeforeStaking = 51_000 ether / uint256(60) * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log18("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            9, // numberOfDelegations
            // 5s of rewards between the delegations; always check if
            // (numberOfDelegations - 1) * rewardsAccruedAfterEach <= rewardsBeforeUnstaking
            5 * 51_000 ether / uint256(3600) * depositAmount / totalDeposit, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 51_000 ether / uint256(60) * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
    }

    function test_OneVsManyStakes_UnstakeAll() public {
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 110_000_000 ether;
        uint256 delegatedAmount = 90_000 ether;
        uint256 rewardsBeforeStaking = 51_000 ether / uint256(60) * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log18("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 51_000 ether / uint256(60) * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            delegation.unbondingPeriod()
        );
    }

    function test_ClaimsAfterManyUnstakings() public {
        claimsAfterManyUnstakings(
            LiquidDelegation(proxy), //delegation
            20 //steps
        );
    }

    // Fuzz testing starts here

    // Foundry tests are stateless i.e. a new contract is deployed each time a test function is called,
    // hence we do fuzzing "manually"

    uint256 constant numOfUsers = 1_000;
    uint256 constant numOfStakings = 5_000;
    uint256 constant numOfRounds = 25_000;
    address[] users; 
    mapping(address => uint256) stakedZil;
    mapping(address => uint256) unstakedZil;
    mapping(address => uint256) earnedZil;
    uint256 stakingsCounter;
    uint256 unstakingsCounter;
    uint256 claimingsCounter;

    function test_RandomStakeUnstakeClaim() external {
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 depositAmount = vm.randomUint(10_000_000 ether, 100_000_000 ether);
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        Console.log("%s total deposit", totalDeposit);
        Console.log("%s initial deposit", depositAmount);
        for (uint256 i = 0; i < numOfUsers; i++) {
            address user = vm.randomAddress();
            users.push(user);
            vm.deal(user, vm.randomUint(100 ether, 100_000_000 ether));
        }
        uint256 lastPrice = 1 ether;
        uint256 totalStakedZil;
        uint256 totalUnstakedZil;
        uint256 totalWithdrawnZil;
        uint256 totalEarnedZil;
        for (uint256 i = 0; i < numOfRounds; i++) {
            uint256 blocks = vm.randomUint(0, 100);
            vm.roll(block.number + blocks);
            uint256 rewards = 51_000 ether * blocks * depositAmount / 3_600 / totalDeposit;
            rewards = rewards * vm.randomUint(0, 100) / 100;
            vm.deal(address(delegation), address(delegation).balance + rewards);
            if (blocks == 0)
                blocks = 1;
            address user = users[vm.randomUint(0, users.length - 1)];
            // numOfStakings is enough
            uint256 operation = vm.randomUint(stakingsCounter < numOfStakings ? 1 : 2, 10);
            // staking is 10% of the operations attempted
            if (operation == 1) {
                if (user.balance < 100 ether)
                    continue;
                Console.log("block %s avg rewards %s price %s", block.number, rewards / blocks, delegation.getPrice());
                uint256 amount = vm.randomUint(100 ether, user.balance);
                uint256 totalStakeValue = delegation.getPrice() * lst.totalSupply();
                vm.startPrank(user);
                delegation.stake{
                    value: amount
                }();
                vm.stopPrank();
                assertGt(totalStakeValue + amount * 1 ether, delegation.getPrice() * lst.totalSupply(), "updated total stake value incorrect");
                stakedZil[user] += amount;
                totalStakedZil += amount;
                stakingsCounter++;
                Console.log("%s staked %s and has %s staked", user, amount, stakedZil[user]);
            }
            // unstaking is 40% of the operations attempted (20% full unstaking, 20% partial unstaking)
            if (operation >= 2 && operation <= 5) {
                if (lst.balanceOf(user) == 0)
                    continue;
                Console.log("block %s avg rewards %s price %s", block.number, rewards / blocks, delegation.getPrice());
                uint256 amount =
                    operation % 2 == 0 ?
                    vm.randomUint(1, lst.balanceOf(user)):
                    lst.balanceOf(user);
                uint256 pendingBefore = delegation.totalPendingWithdrawals();
                uint256 totalStakeValue = delegation.getPrice() * lst.totalSupply();
                vm.startPrank(user);
                amount = delegation.unstake(
                    amount
                );
                vm.stopPrank();
                assertLt(totalStakeValue - amount * 1 ether, delegation.getPrice() * lst.totalSupply(), "updated total stake value incorrect");
                uint256 totalContribution = delegation.totalPendingWithdrawals() - pendingBefore;
                if (totalContribution < amount)
                    totalWithdrawnZil += amount - totalContribution;
                if (amount > stakedZil[user]) {
                    earnedZil[user] += amount - stakedZil[user];
                    totalStakedZil -= stakedZil[user];
                    stakedZil[user] = 0;
                } else {
                    stakedZil[user] -= amount;
                    totalStakedZil -= amount;
                }
                unstakedZil[user] += amount;
                totalUnstakedZil += amount;
                unstakingsCounter++;
                Console.log("%s unstaked %s and has %s staked", user, amount, stakedZil[user]);
                Console.log("%s unstaked %s and has %s unstaked", user, amount, unstakedZil[user]);
            }
            // claiming is 50% of the operations attempted
            if (operation >= 6) {
                if (unstakedZil[user] == 0)
                    continue;
                Console.log("block %s avg rewards %s price %s", block.number, rewards / blocks, delegation.getPrice());
                uint256 contractBalance = address(delegation).balance;
                uint256 userBalance = user.balance;
                vm.startPrank(user);
                delegation.claim();
                vm.stopPrank();
                uint256 amount = user.balance - userBalance;
                totalWithdrawnZil = totalWithdrawnZil + address(delegation).balance + amount - contractBalance;
                if (amount == 0)
                    continue;
                unstakedZil[user] -= amount;
                claimingsCounter++;
                Console.log("%s claimed %s and has %s unstaked", user, amount, unstakedZil[user]);
            }
            Console.log("round %s of %s", i, numOfRounds);
            assertGe(delegation.getPrice(), lastPrice, "price too low");
            lastPrice = delegation.getPrice();
            assertLt(lastPrice, 1 ether + 1_000_000 gwei, "price too high");
            if (lst.totalSupply() == depositAmount)
                assertEq(totalStakedZil, 0, "stake more than initial deposit");
            assertLe(lst.totalSupply() * lastPrice / 1 ether, delegation.getStake() + delegation.getTaxedRewards() + (delegation.getRewards() - delegation.getTaxedRewards()) * (delegation.DENOMINATOR() - delegation.getCommissionNumerator()) / delegation.DENOMINATOR(), "exposure greater than funds");
            assertEq(totalWithdrawnZil + delegation.totalPendingWithdrawals(), totalUnstakedZil, "owned does not match owed");
        }
        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            //totalStakedZil += stakedZil[user];
            //totalUnstakedZil += unstakedZil[user];
            totalEarnedZil += earnedZil[user];
            Console.log(stakedZil[user], unstakedZil[user], earnedZil[user]);
        }
        Console.log("%s total staked %s total unstaked %s total earned", totalStakedZil, totalUnstakedZil, totalEarnedZil);
        Console.log("%s stakings", stakingsCounter);
        Console.log("%s unstakings", unstakingsCounter);
        Console.log("%s claimings", claimingsCounter);
    }

}