/* solhint-disable no-console, func-name-mixedcase */
// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import {BaseDelegationTest, PopVerifyPrecompile} from "test/BaseDelegation.t.sol";
import {NonLiquidDelegation} from "src/NonLiquidDelegation.sol";
import {NonLiquidDelegationV2} from "src/NonLiquidDelegationV2.sol";
import {BaseDelegation, WithdrawalQueue} from "src/BaseDelegation.sol";
import {Delegation} from "src/Delegation.sol";
import {Deposit} from "@zilliqa/zq2/deposit_v2.sol";
import {Console} from "src/Console.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Vm} from "forge-std/Test.sol";
import "forge-std/console.sol";

contract NonLiquidDelegationTest is BaseDelegationTest {
    NonLiquidDelegationV2 delegation;

    constructor() BaseDelegationTest() {
        oldImplementation = address(new NonLiquidDelegation());
        newImplementation = payable(new NonLiquidDelegationV2());
        initializerCall = abi.encodeWithSelector(
            NonLiquidDelegation.initialize.selector,
            owner
        );
        reinitializerCall = abi.encodeWithSelector(
            NonLiquidDelegationV2.reinitialize.selector
        );
    }

    function storeDelegation() internal override {
        delegation = NonLiquidDelegationV2(
            proxy
        );
    }

    function findStaker(address a) internal view returns(uint256) {
        for (uint256 i = 0; i < stakers.length; i++)
            if (stakers[i] == a)
                return i;
        revert("staker not found");
    }  

    function snapshot(string memory s, uint256 i, uint256 x) internal {
        console.log("-----------------------------------------------");
        console.log(s, i, x);
        uint256[] memory shares = new uint256[](stakers.length);
        NonLiquidDelegationV2.Staking[] memory stakings = delegation.getStakingHistory();
        for (i = 0; i < stakings.length; i++)
        //i = stakings.length - 1;
        {
            uint256 stakerIndex = findStaker(stakings[i].staker);
            shares[stakerIndex] = stakings[i].amount;
            s = string.concat("index: ", Strings.toString(i));
            s = string.concat(s, "\tstaker ");
            assertEq(stakings[i].staker, stakers[stakerIndex], "found staker mismatch");
            s = string.concat(s, Strings.toString(stakerIndex + 1));
            s = string.concat(s, ": ");
            s = string.concat(s, Strings.toHexString(stakings[i].staker));
            s = string.concat(s, "   amount: ");
            s = string.concat(s, Strings.toString(stakings[i].amount / 1 ether));
            s = string.concat(s, "\ttotal: ");
            s = string.concat(s, Strings.toString(stakings[i].total / 1 ether));
            if (stakings[i].total < 100_000_000 ether)
                s = string.concat(s, "\t");
            s = string.concat(s, "\trewards: ");
            s = string.concat(s, Strings.toString(stakings[i].rewards / 1 ether));
            s = string.concat(s, "\tshares: ");
            for (uint256 j = 0; j < shares.length; j++)
                if (stakings[i].total != 0) {
                    string memory s0 = string.concat(Console.toString(10**6 * shares[j] / stakings[i].total, 4), "%");
                    if (bytes(s0).length <= 7)
                        s0 = string.concat(s0, "\t\t");
                    else
                        s0 = string.concat(s0, "\t");
                    s = string.concat(s, s0);
                } else
                    s = string.concat(s, "0.0%\t\t");
            console.log(s);
        } 
        (
            uint64[] memory stakingIndices,
            uint64 firstStakingIndex,
            uint256 allWithdrawnRewards,
            uint64 lastWithdrawnRewardIndex,
            uint256 withdrawnAfterLastStaking
        ) = delegation.getStakingData();
        Console.log("stakingIndices = [ %s]", stakingIndices);
        console.log("firstStakingIndex = %s   lastWithdrawnRewardIndex = %s", uint(firstStakingIndex), uint(lastWithdrawnRewardIndex));
        console.log("allWithdrawnRewards = %s   withdrawnAfterLastStaking = %s", allWithdrawnRewards, withdrawnAfterLastStaking);
    } 

    //TODO: add assertions
    function run (
        bytes memory _stakerIndicesBeforeWithdrawals,
        // each element in the interval (-100, 100)
        // if element negative, unstake -depositAmount * element / 10
        // otherwise stake depositAmount * element / 10
        bytes memory _relativeAmountsBeforeWithdrawals,
        bytes memory _stakerIndicesAfterWithdrawals,
        bytes memory _relativeAmountsAfterWithdrawals,
        // 123_456_789 means always withdraw all rewards
        uint64 withdrawalInSteps,
        uint256 depositAmount,
        uint256 rewardsBeforeStaking,
        uint256 rewardsAccruedAfterEach,
        bool initialDeposit
    ) public {
        uint64 steps = withdrawalInSteps;
        uint256[] memory stakerIndicesBeforeWithdrawals = abi.decode(_stakerIndicesBeforeWithdrawals, (uint256[]));
        int256[] memory relativeAmountsBeforeWithdrawals = abi.decode(_relativeAmountsBeforeWithdrawals, (int256[]));
        require(stakerIndicesBeforeWithdrawals.length == relativeAmountsBeforeWithdrawals.length, "array length mismatch");
        uint256[] memory stakerIndicesAfterWithdrawals = abi.decode(_stakerIndicesAfterWithdrawals, (uint256[]));
        int256[] memory relativeAmountsAfterWithdrawals = abi.decode(_relativeAmountsAfterWithdrawals, (int256[]));
        require(stakerIndicesAfterWithdrawals.length == relativeAmountsAfterWithdrawals.length, "array length mismatch");

        if (initialDeposit)
            // otherwise snapshot() doesn't find the staker and reverts
            stakers[0] = owner;
        deposit(BaseDelegation(delegation), depositAmount, initialDeposit);

        for (uint256 i = 0; i < stakers.length; i++) {
            vm.deal(stakers[i], 10 * depositAmount);
            console.log("staker %s: %s", i+1, stakers[i]);
        } 

        delegation = NonLiquidDelegationV2(proxy);

        // rewards accrued so far
        vm.deal(address(delegation), rewardsBeforeStaking - rewardsAccruedAfterEach);

        for (uint256 i = 0; i < stakerIndicesBeforeWithdrawals.length; i++) {
            vm.deal(address(delegation), address(delegation).balance + rewardsAccruedAfterEach);
            int256 x = relativeAmountsBeforeWithdrawals[i] * int256(depositAmount) / 10;
            vm.startPrank(stakers[stakerIndicesBeforeWithdrawals[i]-1]);
            if (x >= 0) {
                delegation.stake{value: uint256(x)}();
                //snapshot("staker %s staked %s", stakerIndices[i], uint256(x));
            }  else {
                 delegation.unstake(uint256(-x));
                //snapshot("staker %s unstaked %s", stakerIndices[i], uint256(-x));
            }
            vm.stopPrank();
            // wait 2 epochs for the change to the deposit to take affect
            vm.roll(block.number + Deposit(delegation.DEPOSIT_CONTRACT()).blocksPerEpoch() * 2);
        }

        //no rewards if we withdraw in the same block as the last staking
        //vm.deal(address(delegation), address(delegation).balance + rewardsAccruedAfterEach);

        for (uint256 i = 1; i <= 2; i++) {
            vm.startPrank(stakers[i-1]);
            if (steps == 123_456_789)
                snapshot("staker %s withdrawing all, remaining rewards:", i, 0);
            else
                snapshot("staker %s withdrawing 1+%s times", i, steps);
            Console.log("rewards accrued until last staking: %s.%s%s", delegation.getTotalRewards());
            Console.log("delegation contract balance: %s.%s%s", address(delegation).balance);
            //Console.log("staker balance: %s.%s%s", stakers[i-1].balance);
            Console.log("staker rewards: %s.%s%s", delegation.rewards());
            if (steps == 123_456_789)
                Console.log("staker withdrew: %s.%s%s", delegation.withdrawAllRewards());
            else
                Console.log("staker withdrew: %s.%s%s", delegation.withdrawRewards(delegation.rewards(steps), steps));
            Console.log("rewards accrued until last staking: %s.%s%s", delegation.getTotalRewards());
            Console.log("delegation contract balance: %s.%s%s", address(delegation).balance);
            //Console.log("staker balance: %s.%s%s", stakers[i-1].balance);
            vm.stopPrank();
        }

        for (uint256 i = 0; i < stakerIndicesAfterWithdrawals.length; i++) {
            vm.deal(address(delegation), address(delegation).balance + rewardsAccruedAfterEach);
            int256 x = relativeAmountsAfterWithdrawals[i] * int256(depositAmount) / 10;
            vm.startPrank(stakers[stakerIndicesAfterWithdrawals[i]-1]);
            if (x >= 0) {
                delegation.stake{value: uint256(x)}();
                //snapshot("staker %s staked %s", stakerIndices[i], uint256(x));
            }  else {
                 delegation.unstake(uint256(-x));
                //snapshot("staker %s unstaked %s", stakerIndices[i], uint256(-x));
            }
            vm.stopPrank();
            // wait 2 epochs for the change to the deposit to take affect
            vm.roll(block.number + Deposit(delegation.DEPOSIT_CONTRACT()).blocksPerEpoch() * 2);
        }

        //further rewards accrued since the last staking
        vm.deal(address(delegation), address(delegation).balance + rewardsAccruedAfterEach);

        for (uint256 i = 1; i <= stakers.length; i++) {
            vm.startPrank(stakers[i-1]);
            if (steps == 123_456_789)
                snapshot("staker %s withdrawing all, remaining rewards:", i, 0);
            else
                snapshot("staker %s withdrawing 1+%s times", i, steps);
            Console.log("rewards accrued until last staking: %s.%s%s", delegation.getTotalRewards());
            Console.log("delegation contract balance: %s.%s%s", address(delegation).balance);
            //Console.log("staker balance: %s.%s%s", stakers[i-1].balance);
            Console.log("staker rewards: %s.%s%s", delegation.rewards());
            if (steps == 123_456_789)
                Console.log("staker withdrew: %s.%s%s", delegation.withdrawAllRewards());
            else
                //TODO: add a test that withdraws a fixed amount < delegation.rewards(step)
                Console.log("staker withdrew: %s.%s%s", delegation.withdrawRewards(delegation.rewards(steps), steps));
            Console.log("rewards accrued until last staking: %s.%s%s", delegation.getTotalRewards());
            Console.log("delegation contract balance: %s.%s%s", address(delegation).balance);
            //Console.log("staker balance: %s.%s%s", stakers[i-1].balance);
            vm.stopPrank();
        }

        // if we try to withdraw again immediately (in the same block),
        // the amount withdrawn must equal zero
        //*
        for (uint256 i = 1; i <= stakers.length; i++) {
            vm.startPrank(stakers[i-1]);
            if (steps == 123_456_789)
                snapshot("staker %s withdrawing all, remaining rewards:", i, 0);
            else
                snapshot("staker %s withdrawing 1+%s times", i, steps);
            Console.log("rewards accrued until last staking: %s.%s%s", delegation.getTotalRewards());
            Console.log("delegation contract balance: %s.%s%s", address(delegation).balance);
            //Console.log("staker balance: %s.%s%s", stakers[i-1].balance);
            Console.log("staker rewards: %s.%s%s", delegation.rewards());
            if (steps == 123_456_789)
                Console.log("staker withdrew: %s.%s%s", delegation.withdrawAllRewards());
            else
                //TODO: add a test that withdraws a fixed amount < delegation.rewards(step)
                Console.log("staker withdrew: %s.%s%s", delegation.withdrawRewards(delegation.rewards(steps), steps));
            Console.log("rewards accrued until last staking: %s.%s%s", delegation.getTotalRewards());
            Console.log("delegation contract balance: %s.%s%s", address(delegation).balance);
            //Console.log("staker balance: %s.%s%s", stakers[i-1].balance);
            vm.stopPrank();
        }
        //*/
    }

    function test_withdrawAllRewards_OwnDeposit() public {
        run(
            abi.encode([uint256(0x20), 5, 1, 2, 3, 1, 2]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 5, 50, 50, 25, 35, -35]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 1, 4]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 1, 40]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            123_456_789, //uint256 withdrawalInSteps,
            10_000_000 ether, //uint256 depositAmount,
            50_000 ether, //uint256 rewardsBeforeStaking,
            10_000 ether, //uint256 rewardsAccruedAfterEach,
            true //bool initialDeposit
        );
    }

    function test_withdraw1Plus0Rewards_OwnDeposit () public {
        run(
            abi.encode([uint256(0x20), 5, 1, 2, 3, 1, 2]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 5, 50, 50, 25, 35, -35]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 1, 4]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 1, 40]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            0, //uint256 withdrawalInSteps,
            10_000_000 ether, //uint256 depositAmount,
            50_000 ether, //uint256 rewardsBeforeStaking,
            10_000 ether, //uint256 rewardsAccruedAfterEach,
            true //bool initialDeposit
        );
    }

    function test_withdraw1Plus1Rewards_OwnDeposit () public {
        run(
            abi.encode([uint256(0x20), 5, 1, 2, 3, 1, 2]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 5, 50, 50, 25, 35, -35]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 1, 4]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 1, 40]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            1, //uint256 withdrawalInSteps,
            10_000_000 ether, //uint256 depositAmount,
            50_000 ether, //uint256 rewardsBeforeStaking,
            10_000 ether, //uint256 rewardsAccruedAfterEach,
            true //bool initialDeposit
        );
    }

    function test_withdraw1Plus2Rewards_OwnDeposit () public {
        run(
            abi.encode([uint256(0x20), 5, 1, 2, 3, 1, 2]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 5, 50, 50, 25, 35, -35]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 1, 4]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 1, 40]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            2, //uint256 withdrawalInSteps,
            10_000_000 ether, //uint256 depositAmount,
            50_000 ether, //uint256 rewardsBeforeStaking,
            10_000 ether, //uint256 rewardsAccruedAfterEach,
            true //bool initialDeposit
        );
    }

    function test_withdraw1Plus3Rewards_OwnDeposit () public {
        run(
            abi.encode([uint256(0x20), 5, 1, 2, 3, 1, 2]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 5, 50, 50, 25, 35, -35]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 1, 4]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 1, 40]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            3, //uint256 withdrawalInSteps,
            10_000_000 ether, //uint256 depositAmount,
            50_000 ether, //uint256 rewardsBeforeStaking,
            10_000 ether, //uint256 rewardsAccruedAfterEach,
            true //bool initialDeposit
        );
    }

    function test_withdrawAllRewards_DelegatedDeposit() public {
        run(
            abi.encode([uint256(0x20), 5, 1, 2, 3, 1, 2]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 5, 50, 50, 25, 35, -35]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 1, 4]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 1, 40]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            123_456_789, //uint256 withdrawalInSteps,
            10_000_000 ether, //uint256 depositAmount,
            50_000 ether, //uint256 rewardsBeforeStaking,
            10_000 ether, //uint256 rewardsAccruedAfterEach,
            false //bool initialDeposit
        );
    }

    function test_withdraw1Plus0Rewards_DelegatedDeposit () public {
        run(
            abi.encode([uint256(0x20), 5, 1, 2, 3, 1, 2]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 5, 50, 50, 25, 35, -35]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 1, 4]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 1, 40]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            0, //uint256 withdrawalInSteps,
            10_000_000 ether, //uint256 depositAmount,
            50_000 ether, //uint256 rewardsBeforeStaking,
            10_000 ether, //uint256 rewardsAccruedAfterEach,
            false //bool initialDeposit
        );
    }

    function test_withdraw1Plus1Rewards_DelegatedDeposit () public {
        run(
            abi.encode([uint256(0x20), 5, 1, 2, 3, 1, 2]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 5, 50, 50, 25, 35, -35]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 1, 4]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 1, 40]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            1, //uint256 withdrawalInSteps,
            10_000_000 ether, //uint256 depositAmount,
            50_000 ether, //uint256 rewardsBeforeStaking,
            10_000 ether, //uint256 rewardsAccruedAfterEach,
            false //bool initialDeposit
        );
    }

    function test_withdraw1Plus2Rewards_DelegatedDeposit () public {
        run(
            abi.encode([uint256(0x20), 5, 1, 2, 3, 1, 2]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 5, 50, 50, 25, 35, -35]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 1, 4]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 1, 40]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            2, //uint256 withdrawalInSteps,
            10_000_000 ether, //uint256 depositAmount,
            50_000 ether, //uint256 rewardsBeforeStaking,
            10_000 ether, //uint256 rewardsAccruedAfterEach,
            false //bool initialDeposit
        );
    }

    function test_withdraw1Plus3Rewards_DelegatedDeposit () public {
        run(
            abi.encode([uint256(0x20), 5, 1, 2, 3, 1, 2]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 5, 50, 50, 25, 35, -35]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 1, 4]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 1, 40]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            3, //uint256 withdrawalInSteps,
            10_000_000 ether, //uint256 depositAmount,
            50_000 ether, //uint256 rewardsBeforeStaking,
            10_000 ether, //uint256 rewardsAccruedAfterEach,
            false //bool initialDeposit
        );
    }

    // run with
    // forge test -vv --via-ir --gas-report --gas-limit 10000000000 --block-gas-limit 10000000000 --match-test AfterMany
    function test_withdrawAfterManyStakings() public {
        uint256 i;
        uint256 x;
        uint64 steps = 11_000;

        deposit(BaseDelegation(delegation), 10_000_000 ether, true);

        // wait 2 epochs for the change to the deposit to take affect
        vm.roll(block.number + Deposit(delegation.DEPOSIT_CONTRACT()).blocksPerEpoch() * 2);

        for (i = 0; i < 4; i++) {
            vm.deal(stakers[i], 100_000 ether);
            console.log("staker %s: %s", i+1, stakers[i]);
        }

        delegation = NonLiquidDelegationV2(proxy);

        // rewards accrued so far
        vm.deal(address(delegation), 50_000 ether);
        x = 50;
        for (uint256 j = 0; j < steps / 8; j++) {
            for (i = 1; i <= 4; i++) {
                vm.startPrank(stakers[i-1]);
                vm.recordLogs();
                vm.expectEmit(
                    true,
                    false,
                    false,
                    false,
                    address(delegation)
                );
                emit Delegation.Staked(
                    stakers[i-1],
                    x * 1 ether,
                    ""
                );
                delegation.stake{value: x * 1 ether}();
                // wait 2 epochs for the change to the deposit to take affect
                vm.roll(block.number + Deposit(delegation.DEPOSIT_CONTRACT()).blocksPerEpoch() * 2);
                //snapshot("staker %s staked %s", i, x);
                vm.stopPrank();
                vm.deal(address(delegation), address(delegation).balance + 10_000 ether);
            }
            for (i = 1; i <= 4; i++) {
                vm.startPrank(stakers[i-1]);
                vm.recordLogs();
                vm.expectEmit(
                    true,
                    false,
                    false,
                    false,
                    address(delegation)
                );
                emit Delegation.Unstaked(
                    stakers[i-1],
                    x * 1 ether,
                    ""
                );
                delegation.unstake(x * 1 ether);
                // wait 2 epochs for the change to the deposit to take affect
                vm.roll(block.number + Deposit(delegation.DEPOSIT_CONTRACT()).blocksPerEpoch() * 2);
                //snapshot("staker %s unstaked %s", i, x);
                vm.stopPrank();
                vm.deal(address(delegation), address(delegation).balance + 10_000 ether);
            }
        }

        i = 1;
        vm.startPrank(stakers[i-1]);
        //snapshot("staker %s withdrawing 1+%s times", i, steps);
        //Console.log("staker balance: %s.%s%s", stakers[i-1].balance);
        //uint256 rewards = delegation.rewards(steps);
        uint256 rewards = delegation.rewards();
        Console.log("staker rewards: %s.%s%s", rewards);
        rewards = delegation.withdrawRewards(rewards, steps);
        //rewards = delegation.withdrawAllRewards();
        /*
        rewards = delegation.withdrawRewards(1000000, 2000);
        rewards += delegation.withdrawRewards(1000000, 2000);
        rewards += delegation.withdrawRewards(1000000, 2000);
        rewards += delegation.withdrawRewards(1000000, 2000);
        //*/
        Console.log("staker withdrew: %s.%s%s", rewards);
        //Console.log("staker balance: %s.%s%s", stakers[i-1].balance);
        vm.stopPrank();

        vm.roll(block.number + WithdrawalQueue.unbondingPeriod());
        //TODO: remove the next line once https://github.com/Zilliqa/zq2/issues/1761 is fixed
        vm.warp(block.timestamp + WithdrawalQueue.unbondingPeriod());


        i = 1;
        vm.startPrank(stakers[i-1]);
        vm.recordLogs();
        vm.expectEmit(
            true,
            false,
            false,
            false,
            address(delegation)
        );
        emit Delegation.Claimed(
            stakers[i-1],
            steps / 8 * x * 1 ether,
            ""
        );
        delegation.claim();
        vm.stopPrank();
    }

    function test_rewardsAfterWithdrawalLessThanBeforeWithdrawal() public {
        uint256 i;
        uint256 x;

        // otherwise snapshot() doesn't find the staker and reverts
        stakers[0] = owner;
        deposit(BaseDelegation(delegation), 10_000_000 ether, true);

        // wait 2 epochs for the change to the deposit to take affect
        vm.roll(block.number + Deposit(delegation.DEPOSIT_CONTRACT()).blocksPerEpoch() * 2);

        for (i = 0; i < 4; i++) {
            vm.deal(stakers[i], 100_000 ether);
        }

        delegation = NonLiquidDelegationV2(proxy);

        // rewards accrued so far
        vm.deal(address(delegation), 50_000 ether);
        x = 50;
        i = 2;
        vm.startPrank(stakers[i-1]);
        vm.recordLogs();
        vm.expectEmit(
            true,
            false,
            false,
            false,
            address(delegation)
        );
        emit Delegation.Staked(
            stakers[i-1],
            x * 1 ether,
            ""
        );
        delegation.stake{value: x * 1 ether}();

        // wait 2 epochs for the change to the deposit to take affect
        vm.roll(block.number + Deposit(delegation.DEPOSIT_CONTRACT()).blocksPerEpoch() * 2);
        vm.stopPrank();

        vm.deal(address(delegation), address(delegation).balance + 10_000 ether);
        vm.startPrank(stakers[i-1]);
        snapshot("staker %s withdrawing all, remaining rewards:", i, 0);
        console.log("-----------------------------------------------");

        Console.log("contract balance: %s.%s%s", address(delegation).balance);
        Console.log("staker balance: %s.%s%s", stakers[i-1].balance);
        uint256 rewards = delegation.rewards();
        Console.log("staker rewards: %s.%s%s", rewards);

        (
        uint64[] memory stakingIndices,
        uint64 firstStakingIndex,
        uint256 allWithdrawnRewards,
        uint64 lastWithdrawnRewardIndex,
        uint256 withdrawnAfterLastStaking
        ) = delegation.getStakingData();
        Console.log("stakingIndices = [ %s]", stakingIndices);
        console.log("firstStakingIndex = %s   lastWithdrawnRewardIndex = %s", uint(firstStakingIndex), uint(lastWithdrawnRewardIndex));
        console.log("allWithdrawnRewards = %s   withdrawnAfterLastStaking = %s", allWithdrawnRewards, withdrawnAfterLastStaking);

        vm.recordLogs();
        vm.expectEmit(
            true,
            true,
            true,
            true,
            address(delegation)
        );
        emit NonLiquidDelegationV2.RewardPaid(
            stakers[i-1],
            rewards
        );
        rewards = delegation.withdrawAllRewards();

        (
        stakingIndices,
        firstStakingIndex,
        allWithdrawnRewards,
        lastWithdrawnRewardIndex,
        withdrawnAfterLastStaking
        ) = delegation.getStakingData();
        Console.log("stakingIndices = [ %s]", stakingIndices);
        console.log("firstStakingIndex = %s   lastWithdrawnRewardIndex = %s", uint(firstStakingIndex), uint(lastWithdrawnRewardIndex));
        console.log("allWithdrawnRewards = %s   withdrawnAfterLastStaking = %s", allWithdrawnRewards, withdrawnAfterLastStaking);

        Console.log("contract balance: %s.%s%s", address(delegation).balance);
        Console.log("staker balance: %s.%s%s", stakers[i-1].balance);
        Console.log("staker rewards: %s.%s%s", delegation.rewards());
        Console.log("staker should have received: %s.%s%s", rewards);
        vm.stopPrank();
    }

    function test_withdrawAllRewardsThenNoMoreStakings_DelegatedDeposit() public {
        run(
            abi.encode([uint256(0x20), 5, 1, 2, 3, 1, 2]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 5, 50, 50, 25, 35, -35]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 0]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 0]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            123_456_789, //uint256 withdrawalInSteps,
            10_000_000 ether, //uint256 depositAmount,
            50_000 ether, //uint256 rewardsBeforeStaking,
            10_000 ether, //uint256 rewardsAccruedAfterEach,
            false //bool initialDeposit
        );
    }

}