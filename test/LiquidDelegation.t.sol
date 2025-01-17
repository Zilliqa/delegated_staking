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

    LiquidDelegationV2[] internal delegations;
    LiquidDelegationV2 internal delegation;
    NonRebasingLST[] internal lsts;
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
            stakers[stakerIndex].balance
        );

        Console.log("Staker balance before staking: %s.%s%s LST",
            lst.balanceOf(stakers[stakerIndex])
        );

        Console.log("Total supply before staking: %s.%s%s LST", 
            lst.totalSupply()
        );

        ownerZIL = [uint256(0), 0];
        rewardsDelta = rewardsBeforeStaking - taxedRewardsBeforeStaking;
        // will be non-zero if the staker participated in fundraising
        lstBalanceBefore = lst.balanceOf(stakers[stakerIndex]);
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
                stakers[stakerIndex].balance
            );

            Console.log("Staker balance after staking: %s.%s%s LST",
                lst.balanceOf(stakers[stakerIndex])
            );

            Console.log("Total supply after staking: %s.%s%s LST",
                lst.totalSupply()
            );

            vm.deal(address(delegation), address(delegation).balance + rewardsAccruedAfterEach);
            rewardsDelta = delegation.getRewards() - taxedRewardsAfterStaking;
        }

        vm.deal(address(delegation), rewardsBeforeUnstaking);

        lstPrice = 10**18 * 1 ether * ((delegation.getStake() + delegation.getRewards() - (delegation.getRewards() - delegation.getTaxedRewards()) * delegation.getCommissionNumerator() / delegation.DENOMINATOR())) / lst.totalSupply();
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
        
        Console.log("Owner commission after unstaking: %s.%s%s ZIL", 
            ownerZIL[1] - ownerZIL[0]
        );

        Console.log("Deposit after unstaking: %s.%s%s ZIL",
            delegation.getStake()
        );

        rewardsAfterUnstaking = delegation.getRewards();
        Console.log("Rewards after unstaking: %s.%s%s ZIL",
            rewardsAfterUnstaking
        );

        taxedRewardsAfterUnstaking = delegation.getTaxedRewards();
        Console.log("Taxed rewards after unstaking: %s.%s%s ZIL",
            taxedRewardsAfterUnstaking
        );

        stakerBalanceAfterUnstaking = stakers[stakerIndex].balance;
        Console.log("Staker balance after unstaking: %s.%s%s ZIL",
            stakerBalanceAfterUnstaking
        );

        Console.log("Staker balance after unstaking: %s.%s%s LST",
            lst.balanceOf(stakers[stakerIndex])
        );

        Console.log("Total supply after unstaking: %s.%s%s LST", 
            lst.totalSupply()
        );

        vm.roll(block.number + blocksUntil);

        vm.recordLogs();

        unstakedAmount = loggedAmount; // the amount we logged on unstaking
        Console.log("Unstaked amount: %s.%s%s ZIL", unstakedAmount);

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
            stakers[stakerIndex].balance
        );
        assertEq(stakers[stakerIndex].balance, stakerBalanceAfterUnstaking + unstakedAmount, "final staker balance mismatch");

        Console.log("Staker balance after claiming: %s.%s%s LST",
            lst.balanceOf(stakers[stakerIndex])
        );

        Console.log("Total supply after claiming: %s.%s%s LST", 
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
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod()
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
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod()
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
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod()
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
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod()
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
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Transforming);
        run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod()
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
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Transforming);
        run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod()
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
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Transforming);
        run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod()
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
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Transforming);
        run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod()
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
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Fundraising);
        run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod()
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
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Fundraising);
        run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod()
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
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Fundraising);
        run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod()
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
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Fundraising);
        run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod()
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
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod()
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
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod()
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
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod()
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
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod()
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
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod()
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
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod()
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
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Transforming);
        run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod()
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
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Transforming);
        run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod()
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
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Fundraising);
        run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod()
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
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Fundraising);
        run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod()
        );
    }

    // Test cases comparing two pools start here

    function test_Bootstrapping_compare1Vs3Validators() public {
        uint256 depositAmount = 90_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 100 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        (, , , , , , , , uint256 lstPrice1, , , , , , , ) = run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod()
        );
        console.log("====================================================================");
        // delegation and lst point to the last element of delegations and lsts by default
        delegation = delegations[0];
        lst = lsts[0];
        depositAmount = 30_000_000 ether;
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        join(BaseDelegation(delegation), depositAmount, makeAddr("2"), 2);
        join(BaseDelegation(delegation), depositAmount, makeAddr("3"), 3);
        (, , , , , , , , uint256 lstPrice2, , , , , , , ) = run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * 3 * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod()
        );
        assertEq(lstPrice1, lstPrice2, "LST price mismatch");
    }     

    function test_Bootstrapping_Fundraising_compareDepositModes() public {
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 100 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        (, , , , , , , , uint256 lstPrice1, , , , , , , ) = run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod()
        );
        console.log("====================================================================");
        // delegation and lst point to the last element of delegations and lsts by default
        delegation = delegations[0];
        lst = lsts[0];
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Fundraising);
        (, , , , , , , , uint256 lstPrice2, , , , , , , ) = run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod()
        );
        assertEq(lstPrice1, lstPrice2, "LST price mismatch");
    }

    function test_Bootstrapping_Transforming_compareDepositModes() public {
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 100 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        (, , , , , , , , uint256 lstPrice1, , , , , , , ) = run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod()
        );
        console.log("====================================================================");
        // delegation and lst point to the last element of delegations and lsts by default
        delegation = delegations[0];
        lst = lsts[0];
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Transforming);
        (, , , , , , , , uint256 lstPrice2, , , , , , , ) = run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 365 * 24 * 51_000 ether * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod()
        );
        assertEq(lstPrice1, lstPrice2, "LST price mismatch");
    }

    function test_Bootstrapping_compare1Vs9Delegations() public {
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 100 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether / uint256(60) * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        (, , , , , , , , , , , , , , uint256 unstakedAmount1, ) = run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            9, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 51_000 ether / uint256(60) * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod()
        );
        console.log("====================================================================");
        // delegation and lst point to the last element of delegations and lsts by default
        delegation = delegations[0];
        lst = lsts[0];
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        (, , , , , , , , , , , , , , uint256 unstakedAmount2, ) = run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            9 * delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 51_000 ether / uint256(60) * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod()
        );
        assertApproxEqAbs(unstakedAmount1, unstakedAmount2, 10, "unstaked amount not approximately same");
    }

    function test_Bootstrapping_compareJoin2ndAndLeave2nd() public {
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 100 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether / uint256(60) * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        (, , , , , , , , uint256 lstPrice1, , , , , , uint256 unstakedAmount1, ) = run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 51_000 ether / uint256(60) * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod()
        );
        console.log("====================================================================");
        // delegation and lst point to the last element of delegations and lsts by default
        delegation = delegations[0];
        lst = lsts[0];
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        join(BaseDelegation(delegation), depositAmount, makeAddr("2"), 2);
        leave(BaseDelegation(delegation), makeAddr("2"), 2);
        (, , , , , , , , uint256 lstPrice2, , , , , , uint256 unstakedAmount2, ) = run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 51_000 ether / uint256(60) * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod()
        );
        assertEq(lstPrice1, lstPrice2, "LST price mismatch");
        assertEq(unstakedAmount1, unstakedAmount2, "unstaked amount mismatch");
    }

    function test_Bootstrapping_compareJoin2ndAndLeave1st() public {
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 100 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether / uint256(60) * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        (, , , , , , , , uint256 lstPrice1, , , , , , uint256 unstakedAmount1, ) = run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 51_000 ether / uint256(60) * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod()
        );
        console.log("====================================================================");
        // delegation and lst point to the last element of delegations and lsts by default
        delegation = delegations[0];
        lst = lsts[0];
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        join(BaseDelegation(delegation), depositAmount, makeAddr("2"), 2);
        leave(BaseDelegation(delegation), owner, 1);
        (, , , , , , , , uint256 lstPrice2, , , , , , uint256 unstakedAmount2, ) = run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 51_000 ether / uint256(60) * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod()
        );
        assertEq(lstPrice1, lstPrice2, "LST price mismatch");
        assertEq(unstakedAmount1, unstakedAmount2, "unstaked amount mismatch");
    }

    function test_Bootstrapping_compareJoin3AndLeave3() public {
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 delegatedAmount = 100 ether;
        uint256 rewardsBeforeStaking = 365 * 24 * 51_000 ether / uint256(60) * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        deposit(BaseDelegation(delegation), 2 * depositAmount, DepositMode.Bootstrapping);
        (, , , , , , , , uint256 lstPrice1, , , , , , uint256 unstakedAmount1, ) = run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 51_000 ether / uint256(60) * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod()
        );
        console.log("====================================================================");
        // delegation and lst point to the last element of delegations and lsts by default
        delegation = delegations[0];
        lst = lsts[0];
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        join(BaseDelegation(delegation), 4 * depositAmount, makeAddr("2"), 2);
        join(BaseDelegation(delegation), 2 * depositAmount, makeAddr("3"), 3);
        join(BaseDelegation(delegation), 5 * depositAmount, makeAddr("4"), 4);
        leave(BaseDelegation(delegation), makeAddr("2"), 2);
        leave(BaseDelegation(delegation), owner, 1);
        leave(BaseDelegation(delegation), makeAddr("4"), 4);
        (, , , , , , , , uint256 lstPrice2, , , , , , uint256 unstakedAmount2, ) = run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 51_000 ether / uint256(60) * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod()
        );
        assertEq(lstPrice1, lstPrice2, "LST price mismatch");
        assertEq(unstakedAmount1, unstakedAmount2, "unstaked amount mismatch");
    }

    // Additional test cases start here

    function test_Bootstrapping_ManyVsOneStake_UnstakeAll() public {
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 110_000_000 ether;
        uint256 delegatedAmount = 10_000 ether;
        uint256 rewardsBeforeStaking = 51_000 ether / uint256(60) * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            9, // numberOfDelegations
            // 5s of rewards between the delegations; always check if
            // (numberOfDelegations - 1) * rewardsAccruedAfterEach <= rewardsBeforeUnstaking
            5 * 51_000 ether / uint256(3600) * depositAmount / totalDeposit, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 51_000 ether / uint256(60) * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod()
        );
    }

    function test_Bootstrapping_OneVsManyStakes_UnstakeAll() public {
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 110_000_000 ether;
        uint256 delegatedAmount = 90_000 ether;
        uint256 rewardsBeforeStaking = 51_000 ether / uint256(60) * depositAmount / totalDeposit;
        uint256 taxedRewardsBeforeStaking = 0;
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log("taxedRewardsAfterStaking = %s.%s%s", taxedRewardsAfterStaking);
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        run(
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            taxedRewardsAfterStaking + 51_000 ether / uint256(60) * depositAmount / totalDeposit, // rewardsBeforeUnstaking
            WithdrawalQueue.unbondingPeriod()
        );
    }

    function test_claimsAfterManyUnstakings() public {
        claimsAfterManyUnstakings(
            LiquidDelegationV2(proxy), //delegation
            20 //steps
        );
    }

}