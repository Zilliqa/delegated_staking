// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

/* solhint-disable no-console */
import {BaseDelegationTest} from "test/BaseDelegation.t.sol";
import {NonLiquidDelegation} from "src/NonLiquidDelegation.sol";
import {BaseDelegation} from "src/BaseDelegation.sol";
import {WithdrawalQueue} from "src/WithdrawalQueue.sol";
import {IDelegation} from "src/IDelegation.sol";
import {Deposit} from "@zilliqa/zq2/deposit_v4.sol";
import {Console} from "src/Console.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {console} from "forge-std/console.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/* solhint-disable func-name-mixedcase */
contract NonLiquidDelegationTest is BaseDelegationTest {
    using SafeCast for int256;

    NonLiquidDelegation[] internal delegations;
    NonLiquidDelegation internal delegation;

    constructor() BaseDelegationTest() {
        implementation = address(new NonLiquidDelegation());
        initializerCall = abi.encodeWithSelector(
            NonLiquidDelegation.initialize.selector,
            owner
        );
    }

    function storeDelegation() internal override {
        delegation = NonLiquidDelegation(
            proxy
        );
        delegations.push(delegation);
    }

    function findStaker(address a) internal view returns(uint256) {
        for (uint256 i = 0; i < stakers.length; i++)
            if (stakers[i] == a)
                return i;
        if (a == owner)
            return stakers.length;        
        revert(string.concat("staker not found ", Strings.toHexString(a)));
    }  

    function snapshot(string memory s, uint256 i, uint256 x) internal view returns(uint256 calculatedRewards) {
        console.log("-----------------------------------------------");
        console.log(s, i, x);
        uint256[] memory shares = new uint256[](stakers.length + 1);
        NonLiquidDelegation.Staking[] memory stakings = delegation.getStakingHistory();
        for (uint256 k = 0; k < stakings.length; k++) {
            uint256 stakerIndex = findStaker(stakings[k].staker);
            shares[stakerIndex] = stakings[k].amount;
            s = string.concat("index: ", Strings.toString(k));
            if (stakerIndex == stakers.length)
                s = string.concat(s, "\t   owner");
            else {
                s = string.concat(s, "\tstaker ");
                s = string.concat(s, Strings.toString(stakerIndex + 1));
            }
            s = string.concat(s, ": ");
            s = string.concat(s, Strings.toHexString(stakings[k].staker));
            s = string.concat(s, "   amount: ");
            s = string.concat(s, Strings.toString(stakings[k].amount / 1 ether));
            s = string.concat(s, "\ttotal: ");
            s = string.concat(s, Strings.toString(stakings[k].total / 1 ether));
            if (stakings[k].total < 100_000_000 ether)
                s = string.concat(s, "\t");
            s = string.concat(s, "\trewards: ");
            s = string.concat(s, Strings.toString(stakings[k].rewards / 1 ether));
            s = string.concat(s, "\t\tshares:\t");
            for (uint256 j = 0; j < shares.length; j++)
                if (stakings[k].total != 0) {
                    string memory s0 = string.concat(Console.toString(10**6 * shares[j] / stakings[k].total, 4), "%");
                    if (bytes(s0).length < 8)
                        s0 = string.concat(s0, "\t\t");
                    else
                        s0 = string.concat(s0, "\t");
                    s = string.concat(s, s0);
                } else
                    s = string.concat(s, "0.0%\t\t");
            console.log(s);
            if (k < stakings.length - 1)
                calculatedRewards += stakings[k+1].rewards * shares[i-1] / stakings[k].total;
            else
                calculatedRewards += (int256(delegation.getRewards()) - delegation.getImmutableRewards()).toUint256() * shares[i-1] / stakings[k].total;
        } 
        (
            uint64[] memory stakingIndices,
            uint64 firstStakingIndex,
            uint256 allWithdrawnRewards,
            uint64 lastWithdrawnRewardIndex,
            uint256 withdrawnAfterLastStaking
        ) = delegation.getStakingData();
        Console.log("stakingIndices = [ %s]", stakingIndices);
        console.log("firstStakingIndex = %s   lastWithdrawnRewardIndex = %s", uint256(firstStakingIndex), uint256(lastWithdrawnRewardIndex));
        console.log("allWithdrawnRewards = %s   withdrawnAfterLastStaking = %s", allWithdrawnRewards, withdrawnAfterLastStaking);
    } 

    function run(
        bytes memory _stakerIndicesBeforeWithdrawals,
        // each element in the interval (-100, 100)
        // if element negative, unstake - depositAmount * element / 10
        // otherwise stake depositAmount * element / 10
        bytes memory _relativeAmountsBeforeWithdrawals,
        bytes memory _stakerIndicesAfterWithdrawals,
        bytes memory _relativeAmountsAfterWithdrawals,
        // 123_456_789 means always withdraw all rewards
        uint64 steps, //withdrawalInSteps
        uint256 depositAmount,
        uint256 rewardsBeforeStaking,
        uint256 rewardsAccruedAfterEach
    ) internal returns(
        uint256[] memory stakerIndicesBeforeWithdrawals,
        int256[] memory relativeAmountsBeforeWithdrawals,
        uint256[] memory stakerIndicesAfterWithdrawals,
        int256[] memory relativeAmountsAfterWithdrawals,
        uint256[] memory calculatedRewards,
        uint256[] memory availableRewards,
        uint256[] memory withdrawnRewards
    ) {
        return run(
            _stakerIndicesBeforeWithdrawals,
            _relativeAmountsBeforeWithdrawals,
            _stakerIndicesAfterWithdrawals,
            _relativeAmountsAfterWithdrawals,
            steps,
            depositAmount,
            rewardsBeforeStaking,
            rewardsAccruedAfterEach,
            new uint256[](stakers.length),
            new uint256[](stakers.length),
            new uint256[](stakers.length)
        );
    }

    function withdraw(
        uint256 last,
        uint64 steps,
        uint256[] memory calculatedRewards,
        uint256[] memory availableRewards,
        uint256[] memory withdrawnRewards
    ) internal {
        for (uint256 i = 1; i <= last; i++) {
            uint256 _calculatedRewards = calculatedRewards[i-1];
            uint256 _availableRewards = availableRewards[i-1];
            uint256 _withdrawnRewards = withdrawnRewards[i-1];
            vm.startPrank(stakers[i-1]);
            calculatedRewards[i-1] =
                steps == 123_456_789 ?
                snapshot("staker %s withdrawing all, remaining rewards:", i, 0) :
                snapshot("staker %s withdrawing 1+%s times", i, steps);
            Console.log("_calculatedRewards = %s.%s%s", _calculatedRewards);
            Console.log("_availableRewards = %s.%s%s", _availableRewards);
            Console.log("_withdrawnRewards = %s.%s%s", _withdrawnRewards);
            int256 temp = int256(calculatedRewards[i-1]) - int256(withdrawnRewards[i-1] * delegation.DENOMINATOR() / (delegation.DENOMINATOR() - delegation.getCommissionNumerator()));
            calculatedRewards[i-1] = (temp > 0 ? temp : -temp).toUint256();
            int256 totalRewardsBefore = int256(delegation.getImmutableRewards());
            int256 delegationBalanceBefore = int256(address(delegation).balance);
            Console.log("rewards accrued until last staking: %s.%s%s", totalRewardsBefore);
            Console.log("delegation contract balance: %s.%s%s", delegationBalanceBefore);
            //Console.log("staker balance: %s.%s%s", stakers[i-1].balance);
            Console.log("calculated rewards: %s.%s%s", calculatedRewards[i-1] * (delegation.DENOMINATOR() - delegation.getCommissionNumerator()) / delegation.DENOMINATOR());
            availableRewards[i-1] = delegation.rewards();
            Console.log("staker rewards: %s.%s%s", availableRewards[i-1]);
            uint256 withdrawnReward =
                steps == 123_456_789 ?
                delegation.withdrawAllRewards() :
                delegation.withdrawRewards(delegation.rewards(steps), steps);
            Console.log("staker withdrew now: %s.%s%s", withdrawnReward);
            withdrawnRewards[i-1] += withdrawnReward;
            Console.log("staker withdrew altogether: %s.%s%s", withdrawnRewards[i-1]);
            assertApproxEqAbs(
                calculatedRewards[i-1] * (delegation.DENOMINATOR() - delegation.getCommissionNumerator()) / delegation.DENOMINATOR(),
                availableRewards[i-1],
                10,
                "rewards differ from calculated value"
            );
            // TODO: add tests that withdraw an amount < delegation.rewards(step)
            int256 totalRewardsAfter = int256(delegation.getImmutableRewards());
            int256 delegationBalanceAfter = int256(address(delegation).balance);
            Console.log("rewards accrued until last staking: %s.%s%s", totalRewardsAfter);
            Console.log("delegation contract balance: %s.%s%s", delegationBalanceAfter);
            assertEq(
                delegationBalanceBefore - totalRewardsBefore,
                delegationBalanceAfter - totalRewardsAfter,
                "total rewards mismatch"
            );
            //Console.log("staker balance: %s.%s%s", stakers[i-1].balance);
            vm.stopPrank();
        }
    }

    function run(
        bytes memory _stakerIndicesBeforeWithdrawals,
        // each element in the interval (-100, 100)
        // if element negative, unstake - depositAmount * element / 10
        // otherwise stake depositAmount * element / 10
        bytes memory _relativeAmountsBeforeWithdrawals,
        bytes memory _stakerIndicesAfterWithdrawals,
        bytes memory _relativeAmountsAfterWithdrawals,
        // 123_456_789 means always withdraw all rewards
        uint64 steps, //withdrawalInSteps
        uint256 depositAmount,
        uint256 rewardsBeforeStaking,
        uint256 rewardsAccruedAfterEach,
        uint256[] memory prevCalculatedRewards,
        uint256[] memory prevAvailableRewards,
        uint256[] memory prevWithdrawnRewards
    ) internal returns(
        uint256[] memory stakerIndicesBeforeWithdrawals,
        int256[] memory relativeAmountsBeforeWithdrawals,
        uint256[] memory stakerIndicesAfterWithdrawals,
        int256[] memory relativeAmountsAfterWithdrawals,
        uint256[] memory calculatedRewards,
        uint256[] memory availableRewards,
        uint256[] memory withdrawnRewards
    ) {
        stakerIndicesBeforeWithdrawals = abi.decode(_stakerIndicesBeforeWithdrawals, (uint256[]));
        relativeAmountsBeforeWithdrawals = abi.decode(_relativeAmountsBeforeWithdrawals, (int256[]));
        require(stakerIndicesBeforeWithdrawals.length == relativeAmountsBeforeWithdrawals.length, "array length mismatch");
        stakerIndicesAfterWithdrawals = abi.decode(_stakerIndicesAfterWithdrawals, (uint256[]));
        relativeAmountsAfterWithdrawals = abi.decode(_relativeAmountsAfterWithdrawals, (int256[]));
        require(stakerIndicesAfterWithdrawals.length == relativeAmountsAfterWithdrawals.length, "array length mismatch");

        for (uint256 i = 0; i < stakers.length; i++) {
            vm.deal(stakers[i], 20 * depositAmount);
            console.log("staker %s: %s", i+1, stakers[i]);
        } 

        // rewards accrued so far
        vm.deal(address(delegation), address(delegation).balance + rewardsBeforeStaking - rewardsAccruedAfterEach);

        // stake and unstake
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

        // no rewards if we withdraw in the same block as the last staking
        //vm.deal(address(delegation), address(delegation).balance + rewardsAccruedAfterEach);

        calculatedRewards = prevCalculatedRewards;
        availableRewards = prevAvailableRewards;
        withdrawnRewards = prevWithdrawnRewards;

        withdraw(
            2, // only first two stakers
            steps,
            calculatedRewards,
            availableRewards,
            withdrawnRewards
        );

        // stake and unstake
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

        // withdraw rewards 5 times in the same block
        // i.e. without additional reward accrual
        for (uint256 r = 0; r < 5; r++)
            withdraw(
                stakers.length, // all stakers
                steps,
                calculatedRewards,
                availableRewards,
                withdrawnRewards
            );
    }

    // Test cases of depositing first and staking afterwards start here

    function test_Bootstrapping_WithdrawAllRewards() public {
        uint256 depositAmount = 10_000_000 ether;
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        run(
            abi.encode([uint256(0x20), 5, 1, 2, 3, 1, 2]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 5, 50, 50, 25, 35, -35]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 1, 4]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 1, 40]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            123_456_789, //uint256 withdrawalInSteps,
            depositAmount,
            50_000 ether, //uint256 rewardsBeforeStaking,
            10_000 ether //uint256 rewardsAccruedAfterEach
        );
    }

    function test_Bootstrapping_Withdraw1Plus0Rewards () public {
        uint256 depositAmount = 10_000_000 ether;
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        run(
            abi.encode([uint256(0x20), 5, 1, 2, 3, 1, 2]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 5, 50, 50, 25, 35, -35]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 1, 4]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 1, 40]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            0, //uint256 withdrawalInSteps,
            depositAmount,
            50_000 ether, //uint256 rewardsBeforeStaking,
            10_000 ether //uint256 rewardsAccruedAfterEach
        );
    }

    function test_Bootstrapping_Withdraw1Plus1Rewards () public {
        uint256 depositAmount = 10_000_000 ether;
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        run(
            abi.encode([uint256(0x20), 5, 1, 2, 3, 1, 2]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 5, 50, 50, 25, 35, -35]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 1, 4]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 1, 40]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            1, //uint256 withdrawalInSteps,
            depositAmount,
            50_000 ether, //uint256 rewardsBeforeStaking,
            10_000 ether //uint256 rewardsAccruedAfterEach
        );
    }

    function test_Bootstrapping_Withdraw1Plus2Rewards () public {
        uint256 depositAmount = 10_000_000 ether;
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        run(
            abi.encode([uint256(0x20), 5, 1, 2, 3, 1, 2]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 5, 50, 50, 25, 35, -35]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 1, 4]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 1, 40]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            2, //uint256 withdrawalInSteps,
            depositAmount,
            50_000 ether, //uint256 rewardsBeforeStaking,
            10_000 ether //uint256 rewardsAccruedAfterEach
        );
    }

    function test_Bootstrapping_Withdraw1Plus3Rewards () public {
        uint256 depositAmount = 10_000_000 ether;
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        run(
            abi.encode([uint256(0x20), 5, 1, 2, 3, 1, 2]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 5, 50, 50, 25, 35, -35]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 1, 4]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 1, 40]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            3, //uint256 withdrawalInSteps,
            depositAmount,
            50_000 ether, //uint256 rewardsBeforeStaking,
            10_000 ether //uint256 rewardsAccruedAfterEach
        );
    }

    // Test cases of turning a solo staker into a staking pool start here

    function test_Transforming_WithdrawAllRewards() public {
        uint256 depositAmount = 10_000_000 ether;
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Transforming);
        run(
            abi.encode([uint256(0x20), 5, 1, 2, 3, 1, 2]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 5, 50, 50, 25, 35, -35]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 1, 4]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 1, 40]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            123_456_789, //uint256 withdrawalInSteps,
            depositAmount,
            50_000 ether, //uint256 rewardsBeforeStaking,
            10_000 ether //uint256 rewardsAccruedAfterEach
        );
    }

    function test_Transforming_Withdraw1Plus0Rewards () public {
        uint256 depositAmount = 10_000_000 ether;
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Transforming);
        run(
            abi.encode([uint256(0x20), 5, 1, 2, 3, 1, 2]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 5, 50, 50, 25, 35, -35]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 1, 4]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 1, 40]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            0, //uint256 withdrawalInSteps,
            depositAmount,
            50_000 ether, //uint256 rewardsBeforeStaking,
            10_000 ether //uint256 rewardsAccruedAfterEach
        );
    }

    function test_Transforming_Withdraw1Plus1Rewards () public {
        uint256 depositAmount = 10_000_000 ether;
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Transforming);
        run(
            abi.encode([uint256(0x20), 5, 1, 2, 3, 1, 2]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 5, 50, 50, 25, 35, -35]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 1, 4]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 1, 40]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            1, //uint256 withdrawalInSteps,
            depositAmount,
            50_000 ether, //uint256 rewardsBeforeStaking,
            10_000 ether //uint256 rewardsAccruedAfterEach
        );
    }

    function test_Transforming_Withdraw1Plus2Rewards () public {
        uint256 depositAmount = 10_000_000 ether;
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Transforming);
        run(
            abi.encode([uint256(0x20), 5, 1, 2, 3, 1, 2]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 5, 50, 50, 25, 35, -35]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 1, 4]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 1, 40]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            2, //uint256 withdrawalInSteps,
            depositAmount,
            50_000 ether, //uint256 rewardsBeforeStaking,
            10_000 ether //uint256 rewardsAccruedAfterEach
        );
    }

    function test_Transforming_Withdraw1Plus3Rewards () public {
        uint256 depositAmount = 10_000_000 ether;
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Transforming);
        run(
            abi.encode([uint256(0x20), 5, 1, 2, 3, 1, 2]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 5, 50, 50, 25, 35, -35]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 1, 4]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 1, 40]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            3, //uint256 withdrawalInSteps,
            depositAmount,
            50_000 ether, //uint256 rewardsBeforeStaking,
            10_000 ether //uint256 rewardsAccruedAfterEach
        );
    }

    // Test cases of staking first and depositing later start here

    function test_Fundraising_WithdrawAllRewards() public {
        uint256 depositAmount = 10_000_000 ether;
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Fundraising);
        run(
            abi.encode([uint256(0x20), 5, 1, 2, 3, 1, 2]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 5, 50, 50, 25, 35, -35]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 1, 4]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 1, 40]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            123_456_789, //uint256 withdrawalInSteps,
            depositAmount,
            50_000 ether, //uint256 rewardsBeforeStaking,
            10_000 ether //uint256 rewardsAccruedAfterEach
        );
    }

    function test_Fundraising_Withdraw1Plus0Rewards () public {
        uint256 depositAmount = 10_000_000 ether;
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Fundraising);
        run(
            abi.encode([uint256(0x20), 5, 1, 2, 3, 1, 2]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 5, 50, 50, 25, 35, -35]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 1, 4]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 1, 40]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            0, //uint256 withdrawalInSteps,
            depositAmount,
            50_000 ether, //uint256 rewardsBeforeStaking,
            10_000 ether //uint256 rewardsAccruedAfterEach
        );
    }

    function test_Fundraising_Withdraw1Plus1Rewards () public {
        uint256 depositAmount = 10_000_000 ether;
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Fundraising);
        run(
            abi.encode([uint256(0x20), 5, 1, 2, 3, 1, 2]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 5, 50, 50, 25, 35, -35]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 1, 4]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 1, 40]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            1, //uint256 withdrawalInSteps,
            depositAmount,
            50_000 ether, //uint256 rewardsBeforeStaking,
            10_000 ether //uint256 rewardsAccruedAfterEach
        );
    }

    function test_Fundraising_Withdraw1Plus2Rewards () public {
        uint256 depositAmount = 10_000_000 ether;
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Fundraising);
        run(
            abi.encode([uint256(0x20), 5, 1, 2, 3, 1, 2]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 5, 50, 50, 25, 35, -35]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 1, 4]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 1, 40]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            2, //uint256 withdrawalInSteps,
            depositAmount,
            50_000 ether, //uint256 rewardsBeforeStaking,
            10_000 ether //uint256 rewardsAccruedAfterEach
        );
    }

    function test_Fundraising_Withdraw1Plus3Rewards_DelegatedDeposit () public {
        uint256 depositAmount = 10_000_000 ether;
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Fundraising);
        run(
            abi.encode([uint256(0x20), 5, 1, 2, 3, 1, 2]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 5, 50, 50, 25, 35, -35]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 1, 4]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 1, 40]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            3, //uint256 withdrawalInSteps,
            depositAmount,
            50_000 ether, //uint256 rewardsBeforeStaking,
            10_000 ether //uint256 rewardsAccruedAfterEach
        );
    }

    // Test cases comparing two pools start here

    function test_Bootstrapping_Compare1Vs3Validators() public {
        uint256 depositAmount = 90_000_000 ether;
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        address[] memory temp = stakers;
        stakers.push(owner);
        (, , , , , , uint256[] memory withdrawnRewards1) = run(
            abi.encode([uint256(0x20), 5, 1, 2, 3, 1, 2]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 5, 50, 50, 25, 35, -35]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 1, 4]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 1, 40]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            123_456_789, //uint256 withdrawalInSteps,
            depositAmount,
            50_000 ether, //uint256 rewardsBeforeStaking,
            10_000 ether //uint256 rewardsAccruedAfterEach
        );
        uint256 total1;
        for (uint256 i = 0; i < stakers.length; i++)
            total1 += withdrawnRewards1[i];
        console.log("====================================================================");
        stakers = temp;
        // delegation points to the last element of delegations by default
        delegation = delegations[0];
        depositAmount = 30_000_000 ether;
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        stakers.push(owner);
        join(BaseDelegation(delegation), depositAmount, makeAddr("2"), 2);
        stakers.push(makeAddr("2"));
        join(BaseDelegation(delegation), depositAmount, makeAddr("3"), 3);
        stakers.push(makeAddr("3"));
        (, , , , , , uint256[] memory withdrawnRewards2) = run(
            abi.encode([uint256(0x20), 5, 1, 2, 3, 1, 2]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 5, 50, 50, 25, 35, -35]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 1, 4]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 1, 40]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            123_456_789, //uint256 withdrawalInSteps,
            depositAmount,
            50_000 ether, //uint256 rewardsBeforeStaking,
            10_000 ether //uint256 rewardsAccruedAfterEach
        );
        uint256 total2;
        for (uint256 i = 0; i < stakers.length; i++)
            total2 += withdrawnRewards2[i];
        assertApproxEqAbs(total1, total2, 10, "total withdrawn rewards mismatch");
    }

    function test_Bootstrapping_Fundraising_CompareDepositModes() public {
        uint256 depositAmount = 10_000_000 ether;
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        address[] memory temp = stakers;
        stakers.push(owner);
        (, , , , , , uint256[] memory withdrawnRewards1) = run(
            abi.encode([uint256(0x20), 5, 1, 2, 3, 1, 2]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 5, 50, 50, 25, 35, -35]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 1, 4]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 1, 40]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            123_456_789, //uint256 withdrawalInSteps,
            depositAmount,
            50_000 ether, //uint256 rewardsBeforeStaking,
            10_000 ether //uint256 rewardsAccruedAfterEach
        );
        uint256 total1;
        for (uint256 i = 0; i < stakers.length; i++)
            total1 += withdrawnRewards1[i];
        console.log("====================================================================");
        stakers = temp;
        // delegation points to the last element of delegations by default
        delegation = delegations[0];
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Fundraising);
        stakers.push(owner);
        (, , , , , , uint256[] memory withdrawnRewards2) = run(
            abi.encode([uint256(0x20), 5, 1, 2, 3, 1, 2]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 5, 50, 50, 25, 35, -35]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 1, 4]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 1, 40]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            123_456_789, //uint256 withdrawalInSteps,
            depositAmount,
            50_000 ether, //uint256 rewardsBeforeStaking,
            10_000 ether //uint256 rewardsAccruedAfterEach
        );
        uint256 total2;
        for (uint256 i = 0; i < stakers.length; i++)
            total2 += withdrawnRewards2[i];
        assertApproxEqAbs(total1, total2, 10, "total withdrawn rewards mismatch");
    }

    function test_Bootstrapping_Transforming_CompareDepositModes() public {
        uint256 depositAmount = 10_000_000 ether;
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        address[] memory temp = stakers;
        stakers.push(owner);
        (, , , , , , uint256[] memory withdrawnRewards1) = run(
            abi.encode([uint256(0x20), 5, 1, 2, 3, 1, 2]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 5, 50, 50, 25, 35, -35]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 1, 4]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 1, 40]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            123_456_789, //uint256 withdrawalInSteps,
            depositAmount,
            50_000 ether, //uint256 rewardsBeforeStaking,
            10_000 ether //uint256 rewardsAccruedAfterEach
        );
        uint256 total1;
        for (uint256 i = 0; i < stakers.length; i++)
            total1 += withdrawnRewards1[i];
        console.log("====================================================================");
        stakers = temp;
        // delegation points to the last element of delegations by default
        delegation = delegations[0];
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Transforming);
        stakers.push(owner);
        (, , , , , , uint256[] memory withdrawnRewards2) = run(
            abi.encode([uint256(0x20), 5, 1, 2, 3, 1, 2]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 5, 50, 50, 25, 35, -35]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 1, 4]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 1, 40]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            123_456_789, //uint256 withdrawalInSteps,
            depositAmount,
            50_000 ether, //uint256 rewardsBeforeStaking,
            10_000 ether //uint256 rewardsAccruedAfterEach
        );
        uint256 total2;
        for (uint256 i = 0; i < stakers.length; i++)
            total2 += withdrawnRewards2[i];
        assertApproxEqAbs(total1, total2, 10, "total withdrawn rewards mismatch");
    }

    function test_Bootstrapping_CompareDifferentDelegations() public {
        uint256 depositAmount = 10_000_000 ether;
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        address[] memory temp = stakers;
        stakers.push(owner);
        (, , , , , , uint256[] memory withdrawnRewards1) = run(
            abi.encode([uint256(0x20), 5, 1, 2, 3, 1, 2]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 5, 50, 50, 25, 35, -35]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 1, 4]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 1, 40]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            123_456_789, //uint256 withdrawalInSteps,
            depositAmount,
            50_000 ether, //uint256 rewardsBeforeStaking,
            10_000 ether //uint256 rewardsAccruedAfterEach
        );
        uint256 total1;
        for (uint256 i = 0; i < stakers.length; i++)
            total1 += withdrawnRewards1[i];
        console.log("====================================================================");
        stakers = temp;
        // delegation points to the last element of delegations by default
        delegation = delegations[0];
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        stakers.push(owner);
        (, , , , , , uint256[] memory withdrawnRewards2) = run(
            abi.encode([uint256(0x20), 5, 2, 1, 4, 3, 4]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 5, 40, 25, 30, 25, -25]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 1, 3]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 1, 70]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            123_456_789, //uint256 withdrawalInSteps,
            depositAmount,
            50_000 ether, //uint256 rewardsBeforeStaking,
            10_000 ether //uint256 rewardsAccruedAfterEach
        );
        uint256 total2;
        for (uint256 i = 0; i < stakers.length; i++)
            total2 += withdrawnRewards2[i];
        assertApproxEqAbs(total1, total2, 10, "total withdrawn rewards mismatch");
    }

    function test_Bootstrapping_CompareJoin2ndAndLeave2nd() public {
        uint256 depositAmount = 10_000_000 ether;
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        address[] memory temp = stakers;
        stakers.push(owner);
        (, , , , , , uint256[] memory withdrawnRewards1) = run(
            abi.encode([uint256(0x20), 5, 1, 2, 3, 1, 2]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 5, 50, 50, 25, 35, -35]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 1, 4]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 1, 40]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            123_456_789, //uint256 withdrawalInSteps,
            depositAmount,
            50_000 ether, //uint256 rewardsBeforeStaking,
            10_000 ether //uint256 rewardsAccruedAfterEach
        );
        uint256 total1;
        for (uint256 i = 0; i < stakers.length; i++)
            total1 += withdrawnRewards1[i];
        console.log("====================================================================");
        stakers = temp;
        // delegation points to the last element of delegations by default
        delegation = delegations[0];
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        stakers.push(owner);
        join(BaseDelegation(delegation), depositAmount, makeAddr("2"), 2);
        stakers.push(makeAddr("2"));
        vm.startPrank(makeAddr("2"));
        delegation.leave(validator(2));
        vm.stopPrank();
        (, , , , , , uint256[] memory withdrawnRewards2) = run(
            abi.encode([uint256(0x20), 5, 1, 2, 3, 1, 2]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 5, 50, 50, 25, 35, -35]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 1, 4]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 1, 40]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            123_456_789, //uint256 withdrawalInSteps,
            depositAmount,
            50_000 ether, //uint256 rewardsBeforeStaking,
            10_000 ether //uint256 rewardsAccruedAfterEach
        );
        uint256 total2;
        for (uint256 i = 0; i < stakers.length; i++)
            total2 += withdrawnRewards2[i];
        assertApproxEqAbs(total1, total2, 10, "total withdrawn rewards mismatch");
    }

    function test_Bootstrapping_CompareJoin2ndAndLeave1st() public {
        uint256 depositAmount = 10_000_000 ether;
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        address[] memory temp = stakers;
        stakers.push(owner);
        (, , , , , , uint256[] memory withdrawnRewards1) = run(
            abi.encode([uint256(0x20), 5, 1, 2, 3, 1, 2]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 5, 50, 50, 25, 35, -35]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 1, 4]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 1, 40]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            123_456_789, //uint256 withdrawalInSteps,
            depositAmount,
            50_000 ether, //uint256 rewardsBeforeStaking,
            10_000 ether //uint256 rewardsAccruedAfterEach
        );
        uint256 total1;
        for (uint256 i = 0; i < stakers.length; i++)
            total1 += withdrawnRewards1[i];
        console.log("====================================================================");
        stakers = temp;
        // delegation points to the last element of delegations by default
        delegation = delegations[0];
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        stakers.push(owner);
        join(BaseDelegation(delegation), depositAmount, makeAddr("2"), 2);
        stakers.push(makeAddr("2"));
        vm.startPrank(owner);
        delegation.leave(validator(1));
        vm.stopPrank();
        (, , , , , , uint256[] memory withdrawnRewards2) = run(
            abi.encode([uint256(0x20), 5, 1, 2, 3, 1, 2]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 5, 50, 50, 25, 35, -35]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 1, 4]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 1, 40]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            123_456_789, //uint256 withdrawalInSteps,
            depositAmount,
            50_000 ether, //uint256 rewardsBeforeStaking,
            10_000 ether //uint256 rewardsAccruedAfterEach
        );
        uint256 total2;
        for (uint256 i = 0; i < stakers.length; i++)
            total2 += withdrawnRewards2[i];
        assertApproxEqAbs(total1, total2, 10, "total withdrawn rewards mismatch");
    }

    function test_Bootstrapping_CompareJoin3MoreAndLeave3() public {
        uint256 depositAmount = 10_000_000 ether;
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        address[] memory temp = stakers;
        stakers.push(owner);
        (, , , , , , uint256[] memory withdrawnRewards1) = run(
            abi.encode([uint256(0x20), 5, 1, 2, 3, 1, 2]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 5, 50, 50, 25, 35, -35]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 1, 4]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 1, 40]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            123_456_789, //uint256 withdrawalInSteps,
            depositAmount,
            50_000 ether, //uint256 rewardsBeforeStaking,
            10_000 ether //uint256 rewardsAccruedAfterEach
        );
        uint256 total1;
        for (uint256 i = 0; i < stakers.length; i++)
            total1 += withdrawnRewards1[i];
        console.log("====================================================================");
        stakers = temp;
        // delegation points to the last element of delegations by default
        delegation = delegations[0];
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        stakers.push(owner);
        join(BaseDelegation(delegation), 4 * depositAmount, makeAddr("2"), 2);
        stakers.push(makeAddr("2"));
        join(BaseDelegation(delegation), 2 * depositAmount, makeAddr("3"), 3);
        stakers.push(makeAddr("3"));
        join(BaseDelegation(delegation), 5 * depositAmount, makeAddr("4"), 4);
        stakers.push(makeAddr("4"));
        vm.startPrank(makeAddr("2"));
        delegation.leave(validator(2));
        vm.stopPrank();
        vm.startPrank(owner);
        delegation.leave(validator(1));
        vm.stopPrank();
        vm.startPrank(makeAddr("4"));
        delegation.leave(validator(4));
        vm.stopPrank();
        (, , , , , , uint256[] memory withdrawnRewards2) = run(
            abi.encode([uint256(0x20), 5, 1, 2, 3, 1, 2]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 5, 50, 50, 25, 35, -35]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 1, 4]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 1, 40]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            123_456_789, //uint256 withdrawalInSteps,
            depositAmount,
            50_000 ether, //uint256 rewardsBeforeStaking,
            10_000 ether //uint256 rewardsAccruedAfterEach
        );
        uint256 total2;
        for (uint256 i = 0; i < stakers.length; i++)
            total2 += withdrawnRewards2[i];
        assertApproxEqAbs(total1, total2, 10, "total withdrawn rewards mismatch");
    }

    // Additional test cases start here

    function test_LeaveAfterOthersStakedPendingWithdrawalsDepositReduction() public {
        uint256 depositAmount = 10_000_000 ether;
        deposit(BaseDelegation(delegation), 2 * depositAmount, DepositMode.Bootstrapping);
        address[] memory temp = stakers;
        stakers = [temp[0], temp[1]];
        (, , , , uint256[] memory calculatedRewards1, uint256[] memory availableRewards1, uint256[] memory withdrawnRewards1) = run(
            abi.encode([uint256(0x20), 4, 1, 2, 1, 2]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 4, 50, 50, -25, -25]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 2, 2, 1]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 2, 75, 75]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            123_456_789, //uint256 withdrawalInSteps,
            depositAmount,
            50_000 ether, //uint256 rewardsBeforeStaking,
            10_000 ether //uint256 rewardsAccruedAfterEach
        );
        vm.startPrank(owner);
        delegation.unstake(depositAmount);
        vm.stopPrank();
        stakers = temp;
        join(BaseDelegation(delegation), depositAmount, makeAddr("2"), 2);
        stakers.push(makeAddr("2"));
        uint256[] memory calculatedRewards2 = new uint256[](stakers.length);
        calculatedRewards2[0] = calculatedRewards1[0];
        calculatedRewards2[1] = calculatedRewards1[1];
        uint256[] memory availableRewards2 = new uint256[](stakers.length);
        availableRewards2[0] = availableRewards1[0];
        availableRewards2[1] = availableRewards1[1];
        uint256[] memory withdrawnRewards2 = new uint256[](stakers.length);
        withdrawnRewards2[0] = withdrawnRewards1[0];
        withdrawnRewards2[1] = withdrawnRewards1[1];
        vm.startPrank(stakers[0]);
        delegation.unstake(100 * depositAmount / 10);
        vm.stopPrank();
        vm.startPrank(stakers[1]);
        delegation.unstake(100 * depositAmount / 10);
        vm.stopPrank();
        (, , , , , , withdrawnRewards2) = run(
            abi.encode([uint256(0x20), 4, 3, 4, 3, 4]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 4, 50, 50, -25, -25]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 2, 4, 3]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 2, 75, 75]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            123_456_789, //uint256 withdrawalInSteps,
            depositAmount,
            0 ether, //uint256 rewardsBeforeStaking,
            10_000 ether, //uint256 rewardsAccruedAfterEach,
            calculatedRewards2,
            availableRewards2,
            withdrawnRewards2
        );
        // stake and unstake to make pendingWithdrawals > 0 before leaving is initiated
        vm.startPrank(owner);
        vm.deal(owner, owner.balance + 100_000 ether);
        delegation.stake{value: 100_000 ether}();
        delegation.unstake(100_000 ether);
        vm.stopPrank();
        // initiate leaving but it can't be completed because of pending withdrawals
        vm.startPrank(makeAddr("2"));
        assertTrue(delegation.pendingWithdrawals(validator(2)), "there should be pending withdrawals");
        delegation.leave(validator(2));
        assertTrue(delegation.pendingWithdrawals(validator(2)), "there should be pending withdrawals");
        vm.stopPrank();
        // if staker claims which calls withdrawDeposit() before the unbonding period, pendingWithdrawals will not be 0
        vm.startPrank(stakers[4-1]);
        delegation.claim();
        assertTrue(delegation.pendingWithdrawals(validator(2)), "there should be pending withdrawals");
        vm.roll(block.number + delegation.unbondingPeriod());
        vm.stopPrank();
        // stake and unstake but pendingWithdrawals remains 0 after leaving was initiated
        vm.startPrank(owner);
        vm.deal(owner, owner.balance + 100_000 ether);
        delegation.stake{value: 100_000 ether}();
        delegation.unstake(100_000 ether);
        vm.stopPrank();
        // if staker claims which calls withdrawDeposit() after the unbonding period, pendingWithdrawals will be 0
        vm.startPrank(stakers[4-1]);
        delegation.claim();
        assertFalse(delegation.pendingWithdrawals(validator(2)), "there should not be pending withdrawals");
        vm.stopPrank();
        // initiate leaving again, the validator's deposit gets decreased
        vm.startPrank(makeAddr("2"));
        delegation.leave(validator(2));
        // completion of leaving has to wait for the unbonding period
        delegation.completeLeaving(validator(2));
        assertEq(delegation.validators().length, 2, "validator leaving should not be completed yet");
        vm.roll(block.number + delegation.unbondingPeriod());
        // completion of leaving is finally possible 
        delegation.completeLeaving(validator(2));
        assertEq(delegation.validators().length, 1, "validator leaving should be completed");
        vm.stopPrank();
        assertApproxEqAbs(withdrawnRewards1[0], withdrawnRewards2[2], 10, "withdrawn rewards mismatch");
        assertApproxEqAbs(withdrawnRewards1[1], withdrawnRewards2[3], 10, "withdrawn rewards mismatch");
    }

    function test_LeaveAfterOthersStakedNoPendingWithdrawalsDepositReduction() public {
        uint256 depositAmount = 10_000_000 ether;
        deposit(BaseDelegation(delegation), 2 * depositAmount, DepositMode.Bootstrapping);
        address[] memory temp = stakers;
        stakers = [temp[0], temp[1]];
        (, , , , uint256[] memory calculatedRewards1, uint256[] memory availableRewards1, uint256[] memory withdrawnRewards1) = run(
            abi.encode([uint256(0x20), 4, 1, 2, 1, 2]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 4, 50, 50, -25, -25]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 2, 2, 1]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 2, 75, 75]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            123_456_789, //uint256 withdrawalInSteps,
            depositAmount,
            50_000 ether, //uint256 rewardsBeforeStaking,
            10_000 ether //uint256 rewardsAccruedAfterEach
        );
        vm.startPrank(owner);
        delegation.unstake(depositAmount);
        vm.stopPrank();
        stakers = temp;
        join(BaseDelegation(delegation), depositAmount, makeAddr("2"), 2);
        stakers.push(makeAddr("2"));
        uint256[] memory calculatedRewards2 = new uint256[](stakers.length);
        calculatedRewards2[0] = calculatedRewards1[0];
        calculatedRewards2[1] = calculatedRewards1[1];
        uint256[] memory availableRewards2 = new uint256[](stakers.length);
        availableRewards2[0] = availableRewards1[0];
        availableRewards2[1] = availableRewards1[1];
        uint256[] memory withdrawnRewards2 = new uint256[](stakers.length);
        withdrawnRewards2[0] = withdrawnRewards1[0];
        withdrawnRewards2[1] = withdrawnRewards1[1];
        vm.startPrank(stakers[0]);
        delegation.unstake(100 * depositAmount / 10);
        vm.stopPrank();
        vm.startPrank(stakers[1]);
        delegation.unstake(100 * depositAmount / 10);
        vm.stopPrank();
        (, , , , , , withdrawnRewards2) = run(
            abi.encode([uint256(0x20), 4, 3, 4, 3, 4]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 4, 50, 50, -25, -25]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 2, 4, 3]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 2, 75, 75]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            123_456_789, //uint256 withdrawalInSteps,
            depositAmount,
            0 ether, //uint256 rewardsBeforeStaking,
            10_000 ether, //uint256 rewardsAccruedAfterEach,
            calculatedRewards2,
            availableRewards2,
            withdrawnRewards2
        );
        vm.roll(block.number + delegation.unbondingPeriod());
        // if staker claims which calls withdrawDeposit() after the unbonding period, pendingWithdrawals will be 0
        vm.startPrank(stakers[4-1]);
        delegation.claim();
        assertFalse(delegation.pendingWithdrawals(validator(2)), "there should not be pending withdrawals");
        vm.stopPrank();
        // initiate leaving, the validator's deposit gets decreased
        vm.startPrank(makeAddr("2"));
        delegation.leave(validator(2));
        // completion of leaving has to wait for the unbonding period
        delegation.completeLeaving(validator(2));
        assertEq(delegation.validators().length, 2, "validator leaving should not be completed yet");
        vm.roll(block.number + delegation.unbondingPeriod());
        // completion of leaving is finally possible 
        delegation.completeLeaving(validator(2));
        assertEq(delegation.validators().length, 1, "validator leaving should be completed");
        vm.stopPrank();
        assertApproxEqAbs(withdrawnRewards1[0], withdrawnRewards2[2], 10, "withdrawn rewards mismatch");
        assertApproxEqAbs(withdrawnRewards1[1], withdrawnRewards2[3], 10, "withdrawn rewards mismatch");
    }

    function test_LeaveAfterOthersStakedPendingWithdrawalsRefund() public {
        uint256 depositAmount = 10_000_000 ether;
        deposit(BaseDelegation(delegation), 2 * depositAmount, DepositMode.Bootstrapping);
        address[] memory temp = stakers;
        stakers = [temp[0], temp[1]];
        (, , , , uint256[] memory calculatedRewards1, uint256[] memory availableRewards1, uint256[] memory withdrawnRewards1) = run(
            abi.encode([uint256(0x20), 4, 1, 2, 1, 2]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 4, 50, 50, -25, -25]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 2, 2, 1]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 2, 75, 75]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            123_456_789, //uint256 withdrawalInSteps,
            depositAmount,
            50_000 ether, //uint256 rewardsBeforeStaking,
            10_000 ether //uint256 rewardsAccruedAfterEach
        );
        vm.startPrank(owner);
        delegation.unstake(depositAmount);
        vm.stopPrank();
        stakers = temp;
        join(BaseDelegation(delegation), depositAmount, makeAddr("2"), 2);
        stakers.push(makeAddr("2"));
        uint256[] memory calculatedRewards2 = new uint256[](stakers.length);
        calculatedRewards2[0] = calculatedRewards1[0];
        calculatedRewards2[1] = calculatedRewards1[1];
        uint256[] memory availableRewards2 = new uint256[](stakers.length);
        availableRewards2[0] = availableRewards1[0];
        availableRewards2[1] = availableRewards1[1];
        uint256[] memory withdrawnRewards2 = new uint256[](stakers.length);
        withdrawnRewards2[0] = withdrawnRewards1[0];
        withdrawnRewards2[1] = withdrawnRewards1[1];
        vm.startPrank(stakers[0]);
        delegation.unstake(100 * depositAmount / 10);
        vm.stopPrank();
        vm.startPrank(stakers[1]);
        delegation.unstake(100 * depositAmount / 10);
        vm.stopPrank();
        (, , , , , , withdrawnRewards2) = run(
            abi.encode([uint256(0x20), 4, 3, 4, 3, 4]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 4, 50, 50, -25, -25]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 2, 4, 3]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 2, 75, 75]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            123_456_789, //uint256 withdrawalInSteps,
            depositAmount,
            0 ether, //uint256 rewardsBeforeStaking,
            10_000 ether, //uint256 rewardsAccruedAfterEach,
            calculatedRewards2,
            availableRewards2,
            withdrawnRewards2
        );
        // stake and unstake to make pendingWithdrawals > 0 before leaving is initiated
        vm.startPrank(owner);
        vm.deal(owner, owner.balance + 100_000 ether);
        delegation.stake{value: 100_000 ether}();
        delegation.unstake(100_000 ether);
        vm.stopPrank();
        // initiate leaving but it can't be completed because of pending withdrawals
        vm.startPrank(makeAddr("2"));
        assertTrue(delegation.pendingWithdrawals(validator(2)), "there should be pending withdrawals");
        delegation.leave(validator(2));
        assertTrue(delegation.pendingWithdrawals(validator(2)), "there should be pending withdrawals");
        vm.stopPrank();
        // if staker claims which calls withdrawDeposit() before the unbonding period, pendingWithdrawals will not be 0
        vm.startPrank(stakers[4-1]);
        delegation.claim();
        assertTrue(delegation.pendingWithdrawals(validator(2)), "there should be pending withdrawals");
        vm.roll(block.number + delegation.unbondingPeriod());
        vm.stopPrank();
        // stake and unstake but pendingWithdrawals remains 0 after leaving was initiated
        vm.startPrank(owner);
        vm.deal(owner, owner.balance + 100_000 ether);
        delegation.stake{value: 100_000 ether}();
        delegation.unstake(100_000 ether);
        vm.stopPrank();
        // control address stakes more than the validator's deposit
        vm.startPrank(makeAddr("2"));
        uint256 amount =
            100 ether +
            1_000_000_000 ether * (delegation.getStake(validator(2)) - delegation.getDelegatedAmount()) /
            (1_000_000_000 ether - 1_000_000_000 ether * delegation.getStake(validator(2)) / (delegation.getStake(validator(1)) + delegation.getStake(validator(2))));
        vm.deal(makeAddr("2"), makeAddr("2").balance + amount);
        delegation.stake{value: amount}();
        uint256 refund = delegation.getDelegatedAmount() - delegation.getStake(validator(2));
        vm.stopPrank();
        // if staker claims which calls withdrawDeposit() after the unbonding period, pendingWithdrawals will be 0
        vm.startPrank(stakers[4-1]);
        delegation.claim();
        assertFalse(delegation.pendingWithdrawals(validator(2)), "there should not be pending withdrawals");
        vm.stopPrank();
        // initiate leaving again, it gets completed instantly, the surplus gets unstaked and can be claimed
        vm.startPrank(makeAddr("2"));
        delegation.leave(validator(2));
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
        assertApproxEqAbs(withdrawnRewards1[0], withdrawnRewards2[2], 10, "withdrawn rewards mismatch");
        assertApproxEqAbs(withdrawnRewards1[1], withdrawnRewards2[3], 10, "withdrawn rewards mismatch");
    }

    function test_LeaveAfterOthersStakedNoPendingWithdrawalsRefund() public {
        uint256 depositAmount = 10_000_000 ether;
        deposit(BaseDelegation(delegation), 2 * depositAmount, DepositMode.Bootstrapping);
        address[] memory temp = stakers;
        stakers = [temp[0], temp[1]];
        (, , , , uint256[] memory calculatedRewards1, uint256[] memory availableRewards1, uint256[] memory withdrawnRewards1) = run(
            abi.encode([uint256(0x20), 4, 1, 2, 1, 2]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 4, 50, 50, -25, -25]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 2, 2, 1]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 2, 75, 75]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            123_456_789, //uint256 withdrawalInSteps,
            depositAmount,
            50_000 ether, //uint256 rewardsBeforeStaking,
            10_000 ether //uint256 rewardsAccruedAfterEach
        );
        vm.startPrank(owner);
        delegation.unstake(depositAmount);
        vm.stopPrank();
        stakers = temp;
        join(BaseDelegation(delegation), depositAmount, makeAddr("2"), 2);
        stakers.push(makeAddr("2"));
        uint256[] memory calculatedRewards2 = new uint256[](stakers.length);
        calculatedRewards2[0] = calculatedRewards1[0];
        calculatedRewards2[1] = calculatedRewards1[1];
        uint256[] memory availableRewards2 = new uint256[](stakers.length);
        availableRewards2[0] = availableRewards1[0];
        availableRewards2[1] = availableRewards1[1];
        uint256[] memory withdrawnRewards2 = new uint256[](stakers.length);
        withdrawnRewards2[0] = withdrawnRewards1[0];
        withdrawnRewards2[1] = withdrawnRewards1[1];
        vm.startPrank(stakers[0]);
        delegation.unstake(100 * depositAmount / 10);
        vm.stopPrank();
        vm.startPrank(stakers[1]);
        delegation.unstake(100 * depositAmount / 10);
        vm.stopPrank();
        (, , , , , , withdrawnRewards2) = run(
            abi.encode([uint256(0x20), 4, 3, 4, 3, 4]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 4, 50, 50, -25, -25]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 2, 4, 3]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 2, 75, 75]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            123_456_789, //uint256 withdrawalInSteps,
            depositAmount,
            0 ether, //uint256 rewardsBeforeStaking,
            10_000 ether, //uint256 rewardsAccruedAfterEach,
            calculatedRewards2,
            availableRewards2,
            withdrawnRewards2
        );
        // control address stakes more than the validator's deposit
        vm.startPrank(makeAddr("2"));
        uint256 amount =
            100 ether +
            1_000_000_000 ether * (delegation.getStake(validator(2)) - delegation.getDelegatedAmount()) /
            (1_000_000_000 ether - 1_000_000_000 ether * delegation.getStake(validator(2)) / (delegation.getStake(validator(1)) + delegation.getStake(validator(2))));
        vm.deal(makeAddr("2"), makeAddr("2").balance + amount);
        delegation.stake{value: amount}();
        uint256 refund = delegation.getDelegatedAmount() - delegation.getStake(validator(2));
        vm.stopPrank();
        vm.roll(block.number + delegation.unbondingPeriod());
        // if staker claims which calls withdrawDeposit() after the unbonding period, pendingWithdrawals will be 0
        vm.startPrank(stakers[4-1]);
        delegation.claim();
        assertFalse(delegation.pendingWithdrawals(validator(2)), "there should not be pending withdrawals");
        vm.stopPrank();
        // initiate leaving, it gets completed instantly, the surplus gets unstaked and can be claimed
        vm.startPrank(makeAddr("2"));
        delegation.leave(validator(2));
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
        assertApproxEqAbs(withdrawnRewards1[0], withdrawnRewards2[2], 10, "withdrawn rewards mismatch");
        assertApproxEqAbs(withdrawnRewards1[1], withdrawnRewards2[3], 10, "withdrawn rewards mismatch");
    }

    function test_LeaveAfterOthersStakedPendingWithdrawalsNoRefund() public {
        uint256 depositAmount = 10_000_000 ether;
        deposit(BaseDelegation(delegation), 2 * depositAmount, DepositMode.Bootstrapping);
        address[] memory temp = stakers;
        stakers = [temp[0], temp[1]];
        (, , , , uint256[] memory calculatedRewards1, uint256[] memory availableRewards1, uint256[] memory withdrawnRewards1) = run(
            abi.encode([uint256(0x20), 4, 1, 2, 1, 2]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 4, 50, 50, -25, -25]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 2, 2, 1]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 2, 75, 75]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            123_456_789, //uint256 withdrawalInSteps,
            depositAmount,
            50_000 ether, //uint256 rewardsBeforeStaking,
            10_000 ether //uint256 rewardsAccruedAfterEach
        );
        vm.startPrank(owner);
        delegation.unstake(depositAmount);
        vm.stopPrank();
        stakers = temp;
        join(BaseDelegation(delegation), depositAmount, makeAddr("2"), 2);
        stakers.push(makeAddr("2"));
        uint256[] memory calculatedRewards2 = new uint256[](stakers.length);
        calculatedRewards2[0] = calculatedRewards1[0];
        calculatedRewards2[1] = calculatedRewards1[1];
        uint256[] memory availableRewards2 = new uint256[](stakers.length);
        availableRewards2[0] = availableRewards1[0];
        availableRewards2[1] = availableRewards1[1];
        uint256[] memory withdrawnRewards2 = new uint256[](stakers.length);
        withdrawnRewards2[0] = withdrawnRewards1[0];
        withdrawnRewards2[1] = withdrawnRewards1[1];
        vm.startPrank(stakers[0]);
        delegation.unstake(100 * depositAmount / 10);
        vm.stopPrank();
        vm.startPrank(stakers[1]);
        delegation.unstake(100 * depositAmount / 10);
        vm.stopPrank();
        (, , , , , , withdrawnRewards2) = run(
            abi.encode([uint256(0x20), 4, 3, 4, 3, 4]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 4, 50, 50, -25, -25]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 2, 4, 3]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 2, 75, 75]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            123_456_789, //uint256 withdrawalInSteps,
            depositAmount,
            0 ether, //uint256 rewardsBeforeStaking,
            10_000 ether, //uint256 rewardsAccruedAfterEach,
            calculatedRewards2,
            availableRewards2,
            withdrawnRewards2
        );
        // stake and unstake to make pendingWithdrawals > 0 before leaving is initiated
        vm.startPrank(owner);
        vm.deal(owner, owner.balance + 1_000_000 ether);
        delegation.stake{value: 1_000_000 ether}();
        delegation.unstake(100_000 ether);
        vm.stopPrank();
        // initiate leaving but it can't be completed because of pending withdrawals
        vm.startPrank(makeAddr("2"));
        assertTrue(delegation.pendingWithdrawals(validator(2)), "there should be pending withdrawals");
        delegation.leave(validator(2));
        assertTrue(delegation.pendingWithdrawals(validator(2)), "there should be pending withdrawals");
        vm.stopPrank();
        // if staker claims which calls withdrawDeposit() before the unbonding period, pendingWithdrawals will not be 0
        vm.startPrank(stakers[4-1]);
        delegation.claim();
        assertTrue(delegation.pendingWithdrawals(validator(2)), "there should be pending withdrawals");
        vm.roll(block.number + delegation.unbondingPeriod());
        vm.stopPrank();
        // stake and unstake but pendingWithdrawals remains 0 after leaving was initiated
        vm.startPrank(owner);
        vm.deal(owner, owner.balance + 100000 ether);
        delegation.stake{value: 100000 ether}();
        delegation.unstake(100000 ether);
        vm.stopPrank();
        // control address stakes as much as the validator's deposit
        vm.startPrank(makeAddr("2"));
        uint256 amount =
            1_000_000_000 ether * (delegation.getStake(validator(2)) - delegation.getDelegatedAmount()) /
            (1_000_000_000 ether - 1_000_000_000 ether * delegation.getStake(validator(2)) / (delegation.getStake(validator(1)) + delegation.getStake(validator(2))));
        vm.deal(makeAddr("2"), makeAddr("2").balance + amount);
        delegation.stake{value: amount}();
        vm.stopPrank();
        // if staker claims which calls withdrawDeposit() after the unbonding period, pendingWithdrawals will be 0
        vm.startPrank(stakers[4-1]);
        delegation.claim();
        assertFalse(delegation.pendingWithdrawals(validator(2)), "there should not be pending withdrawals");
        vm.stopPrank();
        // initiate leaving again, it gets completed instantly, the surplus gets unstaked and can be claimed
        vm.startPrank(makeAddr("2"));
        delegation.leave(validator(2));
        assertEq(delegation.validators().length, 1, "validator leaving should be completed");
        vm.roll(block.number + delegation.unbondingPeriod());
        // there is no refund to claim after the unbonding period 
        uint256 controlAddressBalance = makeAddr("2").balance;
        delegation.claim();
        assertEq(makeAddr("2").balance - controlAddressBalance, 0, "there should be no refund");
        vm.stopPrank();
        assertApproxEqAbs(withdrawnRewards1[0], withdrawnRewards2[2], 10, "withdrawn rewards mismatch");
        assertApproxEqAbs(withdrawnRewards1[1], withdrawnRewards2[3], 10, "withdrawn rewards mismatch");
    }

    function test_LeaveAfterOthersStakedNoPendingWithdrawalsNoRefund() public {
        uint256 depositAmount = 10_000_000 ether;
        deposit(BaseDelegation(delegation), 2 * depositAmount, DepositMode.Bootstrapping);
        address[] memory temp = stakers;
        stakers = [temp[0], temp[1]];
        (, , , , uint256[] memory calculatedRewards1, uint256[] memory availableRewards1, uint256[] memory withdrawnRewards1) = run(
            abi.encode([uint256(0x20), 4, 1, 2, 1, 2]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 4, 50, 50, -25, -25]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 2, 2, 1]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 2, 75, 75]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            123_456_789, //uint256 withdrawalInSteps,
            depositAmount,
            50_000 ether, //uint256 rewardsBeforeStaking,
            10_000 ether //uint256 rewardsAccruedAfterEach
        );
        vm.startPrank(owner);
        delegation.unstake(depositAmount);
        vm.stopPrank();
        stakers = temp;
        join(BaseDelegation(delegation), depositAmount, makeAddr("2"), 2);
        stakers.push(makeAddr("2"));
        uint256[] memory calculatedRewards2 = new uint256[](stakers.length);
        calculatedRewards2[0] = calculatedRewards1[0];
        calculatedRewards2[1] = calculatedRewards1[1];
        uint256[] memory availableRewards2 = new uint256[](stakers.length);
        availableRewards2[0] = availableRewards1[0];
        availableRewards2[1] = availableRewards1[1];
        uint256[] memory withdrawnRewards2 = new uint256[](stakers.length);
        withdrawnRewards2[0] = withdrawnRewards1[0];
        withdrawnRewards2[1] = withdrawnRewards1[1];
        vm.startPrank(stakers[0]);
        delegation.unstake(100 * depositAmount / 10);
        vm.stopPrank();
        vm.startPrank(stakers[1]);
        delegation.unstake(100 * depositAmount / 10);
        vm.stopPrank();
        (, , , , , , withdrawnRewards2) = run(
            abi.encode([uint256(0x20), 4, 3, 4, 3, 4]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 4, 50, 50, -25, -25]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 2, 4, 3]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 2, 75, 75]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            123_456_789, //uint256 withdrawalInSteps,
            depositAmount,
            0 ether, //uint256 rewardsBeforeStaking,
            10_000 ether, //uint256 rewardsAccruedAfterEach,
            calculatedRewards2,
            availableRewards2,
            withdrawnRewards2
        );
        // control address stakes as much as the validator's deposit
        vm.startPrank(makeAddr("2"));
        uint256 amount =
            1_000_000_000 ether * (delegation.getStake(validator(2)) - delegation.getDelegatedAmount()) /
            (1_000_000_000 ether - 1_000_000_000 ether * delegation.getStake(validator(2)) / (delegation.getStake(validator(1)) + delegation.getStake(validator(2))));
        vm.deal(makeAddr("2"), makeAddr("2").balance + amount);
        delegation.stake{value: amount}();
        vm.stopPrank();
        vm.roll(block.number + delegation.unbondingPeriod());
        // if staker claims which calls withdrawDeposit() after the unbonding period, pendingWithdrawals will be 0
        vm.startPrank(stakers[4-1]);
        delegation.claim();
        assertFalse(delegation.pendingWithdrawals(validator(2)), "there should not be pending withdrawals");
        vm.stopPrank();
        // initiate leaving, it gets completed instantly, the surplus gets unstaked and can be claimed
        vm.startPrank(makeAddr("2"));
        delegation.leave(validator(2));
        assertEq(delegation.validators().length, 1, "validator leaving should be completed");
        vm.roll(block.number + delegation.unbondingPeriod());
        // there is no refund to claim after the unbonding period 
        uint256 controlAddressBalance = makeAddr("2").balance;
        delegation.claim();
        assertEq(makeAddr("2").balance - controlAddressBalance, 0, "there should be no refund");
        vm.stopPrank();
        assertApproxEqAbs(withdrawnRewards1[0], withdrawnRewards2[2], 10, "withdrawn rewards mismatch");
        assertApproxEqAbs(withdrawnRewards1[1], withdrawnRewards2[3], 10, "withdrawn rewards mismatch");
    }

    function test_InstantUnstakeBeforeActivation() public {
        vm.deal(stakers[0], stakers[0].balance + 110 ether);
        vm.startPrank(stakers[0]);
        delegation.stake{value: 100 ether}();
        uint256 stakerBalance = stakers[0].balance;
        delegation.unstake(delegation.getDelegatedAmount());
        delegation.claim();
        assertEq(stakers[0].balance - stakerBalance, 100 ether, "balance must increase instantly");
        vm.stopPrank();
    }

    function test_UnstakeNotTooMuch() public {
        uint256 depositAmount = 10_000_000 ether;
        deposit(BaseDelegation(delegation), 2 * depositAmount, DepositMode.Bootstrapping);
        stakers.push(owner);
        join(BaseDelegation(delegation), 2 * depositAmount, makeAddr("2"), 2);
        stakers.push(makeAddr("2"));
        join(BaseDelegation(delegation), 2 * depositAmount, makeAddr("3"), 3);
        stakers.push(makeAddr("3"));
        join(BaseDelegation(delegation), 2 * depositAmount, makeAddr("4"), 4);
        stakers.push(makeAddr("4"));
        vm.startPrank(makeAddr("2"));
        delegation.unstake(2 * depositAmount);
        vm.stopPrank();
        assertEq(delegation.getStake(validator(1)), 15 * depositAmount / 10, "validator deposits are decreased equally");
        assertEq(delegation.getStake(validator(2)), 15 * depositAmount / 10, "validator deposits are decreased equally");
        assertEq(delegation.getStake(validator(3)), 15 * depositAmount / 10, "validator deposits are decreased equally");
        assertEq(delegation.getStake(validator(4)), 15 * depositAmount / 10, "validator deposits are decreased equally");
        vm.startPrank(makeAddr("3"));
        delegation.unstake(2 * depositAmount);
        vm.stopPrank();
        assertEq(delegation.getStake(validator(1)), 10 * depositAmount / 10, "validator deposits are decreased equally");
        assertEq(delegation.getStake(validator(2)), 10 * depositAmount / 10, "validator deposits are decreased equally");
        assertEq(delegation.getStake(validator(3)), 10 * depositAmount / 10, "validator deposits are decreased equally");
        assertEq(delegation.getStake(validator(4)), 10 * depositAmount / 10, "validator deposits are decreased equally");
    }

    function testFail_UnstakeTooMuch() public {
        uint256 depositAmount = 10_000_000 ether;
        deposit(BaseDelegation(delegation), 2 * depositAmount, DepositMode.Bootstrapping);
        stakers.push(owner);
        join(BaseDelegation(delegation), 2 * depositAmount, makeAddr("2"), 2);
        stakers.push(makeAddr("2"));
        join(BaseDelegation(delegation), 2 * depositAmount, makeAddr("3"), 3);
        stakers.push(makeAddr("3"));
        join(BaseDelegation(delegation), 2 * depositAmount, makeAddr("4"), 4);
        stakers.push(makeAddr("4"));
        vm.startPrank(makeAddr("2"));
        delegation.unstake(2 * depositAmount);
        vm.stopPrank();
        assertEq(delegation.getStake(validator(1)), 15 * depositAmount / 10, "validator deposits are decreased equally");
        assertEq(delegation.getStake(validator(2)), 15 * depositAmount / 10, "validator deposits are decreased equally");
        assertEq(delegation.getStake(validator(3)), 15 * depositAmount / 10, "validator deposits are decreased equally");
        assertEq(delegation.getStake(validator(4)), 15 * depositAmount / 10, "validator deposits are decreased equally");
        vm.startPrank(makeAddr("3"));
        delegation.unstake(2 * depositAmount);
        vm.stopPrank();
        assertEq(delegation.getStake(validator(1)), 10 * depositAmount / 10, "validator deposits are decreased equally");
        assertEq(delegation.getStake(validator(2)), 10 * depositAmount / 10, "validator deposits are decreased equally");
        assertEq(delegation.getStake(validator(3)), 10 * depositAmount / 10, "validator deposits are decreased equally");
        assertEq(delegation.getStake(validator(4)), 10 * depositAmount / 10, "validator deposits are decreased equally");
        vm.startPrank(makeAddr("4"));
        delegation.unstake(2 * depositAmount);
        vm.stopPrank();
    }

    function testFail_DepositTwice_Bootstrapping_Bootstrapping() public {
        uint256 depositAmount = 10_000_000 ether;
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
    }

    function testFail_DepositTwice_Bootstrapping_Fundraising() public {
        uint256 depositAmount = 10_000_000 ether;
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Fundraising);
    }

    function testFail_DepositTwice_Fundraising_Fundraising() public {
        uint256 depositAmount = 10_000_000 ether;
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Fundraising);
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Fundraising);
    }

    function testFail_DepositTwice_Fundraising_Bootstrapping() public {
        uint256 depositAmount = 10_000_000 ether;
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Fundraising);
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
    }

    function testFail_DepositTwice_Transforming_Bootstrapping() public {
        uint256 depositAmount = 10_000_000 ether;
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Transforming);
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
    }

    function testFail_DepositTwice_Transforming_Fundraising() public {
        uint256 depositAmount = 10_000_000 ether;
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Transforming);
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Fundraising);
    }

    // run with
    // forge test -vv --via-ir --gas-report --gas-limit 10000000000 --block-gas-limit 10000000000 --match-test AfterMany
    function test_WithdrawAfterManyStakings() public {
        uint256 i;
        uint256 x;
        uint64 steps = 11_000;

        deposit(BaseDelegation(delegation), 10_000_000 ether, DepositMode.Bootstrapping);

        // wait 2 epochs for the change to the deposit to take affect
        vm.roll(block.number + Deposit(delegation.DEPOSIT_CONTRACT()).blocksPerEpoch() * 2);

        for (i = 0; i < 4; i++) {
            vm.deal(stakers[i], 200_000 ether);
            console.log("staker %s: %s", i+1, stakers[i]);
        }

        // rewards accrued so far
        vm.deal(address(delegation), 50_000 ether);
        x = 100;
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
                emit IDelegation.Staked(
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
                emit IDelegation.Unstaked(
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

        vm.roll(block.number + delegation.unbondingPeriod());

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
        emit IDelegation.Claimed(
            stakers[i-1],
            steps / 8 * x * 1 ether,
            ""
        );
        delegation.claim();
        vm.stopPrank();
    }

    // run with
    // forge test -vv --via-ir --gas-report --gas-limit 10000000000 --block-gas-limit 10000000000 --match-test AfterMany
    function test_ReplaceAndWithdrawAfterManyStakings() public {
        uint256 i;
        uint256 x;
        uint64 steps = 11_000;

        deposit(BaseDelegation(delegation), 10_000_000 ether, DepositMode.Bootstrapping);

        // wait 2 epochs for the change to the deposit to take affect
        vm.roll(block.number + Deposit(delegation.DEPOSIT_CONTRACT()).blocksPerEpoch() * 2);

        for (i = 0; i < 4; i++) {
            vm.deal(stakers[i], 200_000 ether);
            console.log("staker %s: %s", i+1, stakers[i]);
        }

        // rewards accrued so far
        vm.deal(address(delegation), 50_000 ether);
        x = 100;
        for (uint256 j = 0; j < steps / 8; j++) {
            if (j == steps / 8 / 2)
                for (i = 1; i <= 4; i++) {
                    address old = stakers[i-1];
                    vm.startPrank(old);
                    stakers[i-1] = makeAddr(Strings.toString(i));
                    delegation.setNewAddress(stakers[i-1]);
                    vm.stopPrank();
                    vm.deal(stakers[i-1], stakers[i-1].balance + 200_000 ether);
                    vm.startPrank(stakers[i-1]);
                    delegation.replaceOldAddress(old);
                    vm.stopPrank();
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
                emit IDelegation.Staked(
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
                emit IDelegation.Unstaked(
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

        vm.roll(block.number + delegation.unbondingPeriod());

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
        emit IDelegation.Claimed(
            stakers[i-1],
            steps / 8 * x * 1 ether,
            ""
        );
        delegation.claim();
        vm.stopPrank();
    }

    function test_ClaimsAfterManyUnstakings() public {
        claimsAfterManyUnstakings(
            NonLiquidDelegation(proxy), //delegation
            20 //steps
        );
    }

    function test_RewardsAfterWithdrawalLessThanBeforeWithdrawal() public {
        uint256 i;
        uint256 x;

        deposit(BaseDelegation(delegation), 10_000_000 ether, DepositMode.Bootstrapping);

        // wait 2 epochs for the change to the deposit to take affect
        vm.roll(block.number + Deposit(delegation.DEPOSIT_CONTRACT()).blocksPerEpoch() * 2);

        for (i = 0; i < 4; i++) {
            vm.deal(stakers[i], 100_000 ether);
        }

        // rewards accrued so far
        vm.deal(address(delegation), 50_000 ether);
        x = 100;
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
        emit IDelegation.Staked(
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
        console.log("firstStakingIndex = %s   lastWithdrawnRewardIndex = %s", uint256(firstStakingIndex), uint256(lastWithdrawnRewardIndex));
        console.log("allWithdrawnRewards = %s   withdrawnAfterLastStaking = %s", allWithdrawnRewards, withdrawnAfterLastStaking);

        vm.recordLogs();
        vm.expectEmit(
            true,
            true,
            true,
            true,
            address(delegation)
        );
        emit NonLiquidDelegation.RewardPaid(
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
        console.log("firstStakingIndex = %s   lastWithdrawnRewardIndex = %s", uint256(firstStakingIndex), uint256(lastWithdrawnRewardIndex));
        console.log("allWithdrawnRewards = %s   withdrawnAfterLastStaking = %s", allWithdrawnRewards, withdrawnAfterLastStaking);

        Console.log("contract balance: %s.%s%s", address(delegation).balance);
        Console.log("staker balance: %s.%s%s", stakers[i-1].balance);
        Console.log("staker rewards: %s.%s%s", delegation.rewards());
        Console.log("staker should have received: %s.%s%s", rewards);
        vm.stopPrank();
    }

    function test_Fundraising_WithdrawAllRewardsThenNoMoreStakings() public {
        uint256 depositAmount = 10_000_000 ether;
        deposit(BaseDelegation(delegation), depositAmount, DepositMode.Fundraising);
        run(
            abi.encode([uint256(0x20), 5, 1, 2, 3, 1, 2]), //bytes -> uint256[] memory stakerIndicesBeforeWithdrawals,
            abi.encode([int256(0x20), 5, 50, 50, 25, 35, -35]), //bytes -> int256[] memory relativeAmountsBeforeWithdrawals,
            abi.encode([uint256(0x20), 0]), //bytes -> uint256[] memory stakerIndicesAfterWithdrawals,
            abi.encode([int256(0x20), 0]), //bytes -> int256[] memory relativeAmountsAfterWithdrawals,
            123_456_789, //uint256 withdrawalInSteps,
            depositAmount,
            50_000 ether, //uint256 rewardsBeforeStaking,
            10_000 ether //uint256 rewardsAccruedAfterEach
        );
    }

}