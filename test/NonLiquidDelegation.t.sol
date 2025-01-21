// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

/* solhint-disable no-console */
import {BaseDelegationTest} from "test/BaseDelegation.t.sol";
import {NonLiquidDelegation} from "src/NonLiquidDelegation.sol";
import {NonLiquidDelegationV2} from "src/NonLiquidDelegationV2.sol";
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

    NonLiquidDelegationV2[] internal delegations;
    NonLiquidDelegationV2 internal delegation;

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
        delegations.push(delegation);
    }

    function findStaker(address a) internal view returns(uint256) {
        if (a == owner)
            return stakers.length;        
        for (uint256 i = 0; i < stakers.length; i++)
            if (stakers[i] == a)
                return i;
        revert(string.concat("staker not found ", Strings.toHexString(a)));
    }  

    function snapshot(string memory s, uint256 i, uint256 x) internal view returns(uint256 calculatedRewards) {
        console.log("-----------------------------------------------");
        console.log(s, i, x);
        uint256[] memory shares = new uint256[](stakers.length + 1);
        NonLiquidDelegationV2.Staking[] memory stakings = delegation.getStakingHistory();
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
                calculatedRewards += (int256(delegation.getRewards()) - delegation.getTotalRewards()).toUint256() * shares[i-1] / stakings[k].total;
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
        stakerIndicesBeforeWithdrawals = abi.decode(_stakerIndicesBeforeWithdrawals, (uint256[]));
        relativeAmountsBeforeWithdrawals = abi.decode(_relativeAmountsBeforeWithdrawals, (int256[]));
        require(stakerIndicesBeforeWithdrawals.length == relativeAmountsBeforeWithdrawals.length, "array length mismatch");
        stakerIndicesAfterWithdrawals = abi.decode(_stakerIndicesAfterWithdrawals, (uint256[]));
        relativeAmountsAfterWithdrawals = abi.decode(_relativeAmountsAfterWithdrawals, (int256[]));
        require(stakerIndicesAfterWithdrawals.length == relativeAmountsAfterWithdrawals.length, "array length mismatch");

        for (uint256 i = 0; i < stakers.length; i++) {
            vm.deal(stakers[i], 10 * depositAmount);
            console.log("staker %s: %s", i+1, stakers[i]);
        } 

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

        // no rewards if we withdraw in the same block as the last staking
        //vm.deal(address(delegation), address(delegation).balance + rewardsAccruedAfterEach);

        calculatedRewards = new uint256[](stakers.length);
        availableRewards = new uint256[](stakers.length);
        withdrawnRewards = new uint256[](stakers.length);
        for (uint256 i = 1; i <= 2; i++) {
            vm.startPrank(stakers[i-1]);
            calculatedRewards[i-1] =
                steps == 123_456_789 ?
                snapshot("staker %s withdrawing all, remaining rewards:", i, 0) :
                snapshot("staker %s withdrawing 1+%s times", i, steps);
            Console.log("rewards accrued until last staking: %s.%s%s", delegation.getTotalRewards());
            Console.log("delegation contract balance: %s.%s%s", address(delegation).balance);
            //Console.log("staker balance: %s.%s%s", stakers[i-1].balance);
            Console.log("calculated rewards: %s.%s%s", calculatedRewards[i-1] * (delegation.DENOMINATOR() - delegation.getCommissionNumerator()) / delegation.DENOMINATOR());
            availableRewards[i-1] = delegation.rewards();
            Console.log("staker rewards: %s.%s%s", availableRewards[i-1]);
            withdrawnRewards[i-1] =
                steps == 123_456_789 ?
                delegation.withdrawAllRewards() :
                delegation.withdrawRewards(delegation.rewards(steps), steps);
            Console.log("staker withdrew: %s.%s%s", withdrawnRewards[i-1]);
            assertApproxEqAbs(
                calculatedRewards[i-1] * (delegation.DENOMINATOR() - delegation.getCommissionNumerator()) / delegation.DENOMINATOR(),
                availableRewards[i-1],
                9,
                "rewards differ from calculated value"
            );
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

        // withdraw rewards 5 times in the same block
        // i.e. without additional reward accrual
        for (uint256 r = 0; r < 5; r++)
            for (uint256 i = 1; i <= stakers.length; i++) {
                vm.startPrank(stakers[i-1]);
                calculatedRewards[i-1] =
                    steps == 123_456_789 ?
                    snapshot("staker %s withdrawing all, remaining rewards:", i, 0) :
                    snapshot("staker %s withdrawing 1+%s times", i, steps);
                int256 temp = int256(calculatedRewards[i-1]) - int256(withdrawnRewards[i-1] * delegation.DENOMINATOR() / (delegation.DENOMINATOR() - delegation.getCommissionNumerator()));
                calculatedRewards[i-1] = (temp > 0 ? temp : -temp).toUint256();
                int256 totalRewardsBefore = int256(delegation.getTotalRewards());
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
                    9,
                    "rewards differ from calculated value"
                );
                //TODO: add a test that withdraws a fixed amount < delegation.rewards(step)
                int256 totalRewardsAfter = int256(delegation.getTotalRewards());
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

//TODO: add tests that compare scenarios

//TODO: add tests for joining and leaving of additional validators

//TODO: add test cases where stakers[0] == owner i.e. everything gets unstaked

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

    // Additional test cases start here

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

        delegation = NonLiquidDelegationV2(proxy);

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

        vm.roll(block.number + WithdrawalQueue.unbondingPeriod());

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
            NonLiquidDelegationV2(proxy), //delegation
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

        delegation = NonLiquidDelegationV2(proxy);

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