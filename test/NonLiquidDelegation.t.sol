// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.28;

/* solhint-disable no-console */
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { Deposit } from "@zilliqa/zq2/deposit_v6.sol";
import { Console } from "script/Console.s.sol";
import { BaseDelegation } from "src/BaseDelegation.sol";
import { IDelegation } from "src/IDelegation.sol";
import { NonLiquidDelegation } from "src/NonLiquidDelegation.sol";
import { WithdrawalQueue } from "src/WithdrawalQueue.sol";
import { BaseDelegationTest } from "test/BaseDelegation.t.sol";

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
        Console.log("-----------------------------------------------");
        Console.log(s, i, x);
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
            Console.log(s);
            if (k < stakings.length - 1)
                calculatedRewards += stakings[k+1].rewards * shares[i-1] / stakings[k].total;
            else
                calculatedRewards +=
                    (int256(delegation.getRewards()) - delegation.getHistoricalTaxedRewards()).toUint256() *
                    shares[i-1] / stakings[k].total * 
                    (delegation.DENOMINATOR() - delegation.getCommissionNumerator()) / delegation.DENOMINATOR();
        } 
        (
            uint64[] memory stakingIndices,
            uint64 firstPosInStakingIndices,
            uint256 availableTaxedRewards,
            uint64 lastWithdrawnRewardIndex,
            uint256 taxedSinceLastStaking
        ) = delegation.getStakingData();
        Console.log("stakingIndices = [ %s]", stakingIndices);
        Console.log("firstPosInStakingIndices = %s   lastWithdrawnRewardIndex = %s", uint256(firstPosInStakingIndices), uint256(lastWithdrawnRewardIndex));
        Console.log("availableTaxedRewards = %s   taxedSinceLastStaking = %s", availableTaxedRewards, taxedSinceLastStaking);
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
            Console.log18("_calculatedRewards = %s.%s%s", _calculatedRewards);
            Console.log18("_availableRewards = %s.%s%s", _availableRewards);
            Console.log18("_withdrawnRewards = %s.%s%s", _withdrawnRewards);
            int256 temp = int256(calculatedRewards[i-1]) - int256(withdrawnRewards[i-1]);
            calculatedRewards[i-1] = (temp > 0 ? temp : -temp).toUint256();
            int256 totalRewardsBefore = int256(delegation.getHistoricalTaxedRewards());
            int256 delegationBalanceBefore = int256(address(delegation).balance);
            Console.log18("rewards accrued until last staking: %s.%s%s", totalRewardsBefore);
            Console.log18("delegation contract balance: %s.%s%s", delegationBalanceBefore);
            //Console.log18("staker balance: %s.%s%s", stakers[i-1].balance);
            Console.log18("calculated rewards: %s.%s%s", calculatedRewards[i-1]);
            availableRewards[i-1] = delegation.rewards();
            Console.log18("staker rewards: %s.%s%s", availableRewards[i-1]);
            uint256 withdrawnReward =
                steps == 123_456_789 ?
                delegation.withdrawAllRewards() :
                delegation.withdrawRewards(delegation.rewards(steps), steps);
            Console.log18("staker withdrew now: %s.%s%s", withdrawnReward);
            withdrawnRewards[i-1] += withdrawnReward;
            Console.log18("staker withdrew altogether: %s.%s%s", withdrawnRewards[i-1]);
            assertApproxEqAbs(
                calculatedRewards[i-1],
                availableRewards[i-1],
                10,
                "rewards differ from calculated value"
            );
            int256 totalRewardsAfter = int256(delegation.getHistoricalTaxedRewards());
            int256 delegationBalanceAfter = int256(address(delegation).balance);
            Console.log18("rewards accrued until last staking: %s.%s%s", totalRewardsAfter);
            Console.log18("delegation contract balance: %s.%s%s", delegationBalanceAfter);
            assertEq(
                delegationBalanceBefore - totalRewardsBefore,
                delegationBalanceAfter - totalRewardsAfter,
                "total rewards mismatch"
            );
            //Console.log18("staker balance: %s.%s%s", stakers[i-1].balance);
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
        assert(stakerIndicesBeforeWithdrawals.length == relativeAmountsBeforeWithdrawals.length);
        stakerIndicesAfterWithdrawals = abi.decode(_stakerIndicesAfterWithdrawals, (uint256[]));
        relativeAmountsAfterWithdrawals = abi.decode(_relativeAmountsAfterWithdrawals, (int256[]));
        assert(stakerIndicesAfterWithdrawals.length == relativeAmountsAfterWithdrawals.length);

        for (uint256 i = 0; i < stakers.length; i++) {
            vm.deal(stakers[i], 20 * depositAmount);
            Console.log("staker %s: %s", i+1, stakers[i]);
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
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
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
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
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
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
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
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
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
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
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
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Transforming);
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
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Transforming);
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
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Transforming);
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
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Transforming);
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
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Transforming);
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
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Fundraising);
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
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Fundraising);
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
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Fundraising);
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
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Fundraising);
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
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Fundraising);
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
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
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
        Console.log("====================================================================");
        stakers = temp;
        // delegation points to the last element of delegations by default
        delegation = delegations[0];
        depositAmount = 30_000_000 ether;
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        stakers.push(owner);
        joinPool(BaseDelegation(delegation), depositAmount, makeAddr("2"), 2);
        stakers.push(makeAddr("2"));
        joinPool(BaseDelegation(delegation), depositAmount, makeAddr("3"), 3);
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
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
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
        Console.log("====================================================================");
        stakers = temp;
        // delegation points to the last element of delegations by default
        delegation = delegations[0];
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Fundraising);
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
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
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
        Console.log("====================================================================");
        stakers = temp;
        // delegation points to the last element of delegations by default
        delegation = delegations[0];
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Transforming);
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
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
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
        Console.log("====================================================================");
        stakers = temp;
        // delegation points to the last element of delegations by default
        delegation = delegations[0];
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
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
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
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
        Console.log("====================================================================");
        stakers = temp;
        // delegation points to the last element of delegations by default
        delegation = delegations[0];
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        stakers.push(owner);
        joinPool(BaseDelegation(delegation), depositAmount, makeAddr("2"), 2);
        stakers.push(makeAddr("2"));
        vm.startPrank(makeAddr("2"));
        delegation.leavePool(validator(2));
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
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
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
        Console.log("====================================================================");
        stakers = temp;
        // delegation points to the last element of delegations by default
        delegation = delegations[0];
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        stakers.push(owner);
        joinPool(BaseDelegation(delegation), depositAmount, makeAddr("2"), 2);
        stakers.push(makeAddr("2"));
        vm.startPrank(owner);
        delegation.leavePool(validator(1));
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
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
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
        Console.log("====================================================================");
        stakers = temp;
        // delegation points to the last element of delegations by default
        delegation = delegations[0];
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        stakers.push(owner);
        joinPool(BaseDelegation(delegation), 4 * depositAmount, makeAddr("2"), 2);
        stakers.push(makeAddr("2"));
        joinPool(BaseDelegation(delegation), 2 * depositAmount, makeAddr("3"), 3);
        stakers.push(makeAddr("3"));
        joinPool(BaseDelegation(delegation), 5 * depositAmount, makeAddr("4"), 4);
        stakers.push(makeAddr("4"));
        vm.startPrank(makeAddr("2"));
        delegation.leavePool(validator(2));
        vm.stopPrank();
        vm.startPrank(owner);
        delegation.leavePool(validator(1));
        vm.stopPrank();
        vm.startPrank(makeAddr("4"));
        delegation.leavePool(validator(4));
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
        addValidator(BaseDelegation(delegation), 2 * depositAmount, DepositMode.Bootstrapping);
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
        joinPool(BaseDelegation(delegation), depositAmount, makeAddr("2"), 2);
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
        address staker = stakers[4-1];
        // stake and unstake to make pendingWithdrawals > 0 before leaving is initiated
        vm.startPrank(owner);
        vm.deal(owner, owner.balance + 100_000 ether);
        delegation.stake{value: 100_000 ether}();
        delegation.unstake(100_000 ether);
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
        vm.startPrank(owner);
        vm.deal(owner, owner.balance + 100_000 ether);
        delegation.stake{value: 100_000 ether}();
        delegation.unstake(100_000 ether);
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
        vm.deal(staker, staker.balance + 10_000 ether);
        vm.startPrank(staker);
        delegation.stake{value: 10_000 ether}();
        delegation.unstake(10_000 ether);
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
        assertApproxEqAbs(withdrawnRewards1[0], withdrawnRewards2[2], 10, "withdrawn rewards mismatch");
        assertApproxEqAbs(withdrawnRewards1[1], withdrawnRewards2[3], 10, "withdrawn rewards mismatch");
    }

    function test_LeaveAfterOthersStakedNoPendingWithdrawalsDepositReduction() public {
        uint256 depositAmount = 10_000_000 ether;
        addValidator(BaseDelegation(delegation), 2 * depositAmount, DepositMode.Bootstrapping);
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
        address staker = stakers[1-1];
        vm.startPrank(owner);
        delegation.unstake(depositAmount);
        vm.stopPrank();
        stakers = temp;
        joinPool(BaseDelegation(delegation), depositAmount, makeAddr("2"), 2);
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
        vm.startPrank(staker);
        delegation.claim();
        assertFalse(delegation.pendingWithdrawals(validator(2)), "there should not be pending withdrawals");
        vm.stopPrank();
        // initiate leaving, the validator's deposit gets decreased
        vm.startPrank(makeAddr("2"));
        delegation.leavePool(validator(2));
        // if staker unstakes after the validator requested leaving, the validator's pendingWithdrawals remain 0
        vm.stopPrank();
        vm.deal(staker, staker.balance + 10_000 ether);
        vm.startPrank(staker);
        delegation.stake{value: 10_000 ether}();
        delegation.unstake(10_000 ether);
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
        assertApproxEqAbs(withdrawnRewards1[0], withdrawnRewards2[2], 10, "withdrawn rewards mismatch");
        assertApproxEqAbs(withdrawnRewards1[1], withdrawnRewards2[3], 10, "withdrawn rewards mismatch");
    }

    function test_LeaveAfterOthersStakedPendingWithdrawalsRefund() public {
        uint256 depositAmount = 10_000_000 ether;
        addValidator(BaseDelegation(delegation), 2 * depositAmount, DepositMode.Bootstrapping);
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
        joinPool(BaseDelegation(delegation), depositAmount, makeAddr("2"), 2);
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
        address staker = stakers[4-1];
        // stake and unstake to make pendingWithdrawals > 0 before leaving is initiated
        vm.startPrank(owner);
        vm.deal(owner, owner.balance + 100_000 ether);
        delegation.stake{value: 100_000 ether}();
        delegation.unstake(100_000 ether);
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
        vm.startPrank(owner);
        vm.deal(owner, owner.balance + 100_000 ether);
        delegation.stake{value: 100_000 ether}();
        delegation.unstake(100_000 ether);
        vm.stopPrank();
        // control address stakes more than the validator's deposit
        vm.startPrank(makeAddr("2"));
        uint256 amount =
            100 ether +
            1_000_000_000 ether * (delegation.getDeposit(validator(2)) - delegation.getDelegatedAmount()) /
            (1_000_000_000 ether - 1_000_000_000 ether * delegation.getDeposit(validator(2)) / (delegation.getDeposit(validator(1)) + delegation.getDeposit(validator(2))));
        vm.deal(makeAddr("2"), makeAddr("2").balance + amount);
        delegation.stake{value: amount}();
        uint256 refund = delegation.getDelegatedAmount() - delegation.getDeposit(validator(2));
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
        assertApproxEqAbs(withdrawnRewards1[0], withdrawnRewards2[2], 10, "withdrawn rewards mismatch");
        assertApproxEqAbs(withdrawnRewards1[1], withdrawnRewards2[3], 10, "withdrawn rewards mismatch");
    }

    function test_LeaveAfterOthersStakedNoPendingWithdrawalsRefund() public {
        uint256 depositAmount = 10_000_000 ether;
        addValidator(BaseDelegation(delegation), 2 * depositAmount, DepositMode.Bootstrapping);
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
        joinPool(BaseDelegation(delegation), depositAmount, makeAddr("2"), 2);
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
        address staker = stakers[4-1];
        // control address stakes more than the validator's deposit
        vm.startPrank(makeAddr("2"));
        uint256 amount =
            100 ether +
            1_000_000_000 ether * (delegation.getDeposit(validator(2)) - delegation.getDelegatedAmount()) /
            (1_000_000_000 ether - 1_000_000_000 ether * delegation.getDeposit(validator(2)) / (delegation.getDeposit(validator(1)) + delegation.getDeposit(validator(2))));
        vm.deal(makeAddr("2"), makeAddr("2").balance + amount);
        delegation.stake{value: amount}();
        uint256 refund = delegation.getDelegatedAmount() - delegation.getDeposit(validator(2));
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
        addValidator(BaseDelegation(delegation), 2 * depositAmount, DepositMode.Bootstrapping);
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
        joinPool(BaseDelegation(delegation), depositAmount, makeAddr("2"), 2);
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
        address staker = stakers[4-1];
        // stake and unstake to make pendingWithdrawals > 0 before leaving is initiated
        vm.startPrank(owner);
        vm.deal(owner, owner.balance + 1_000_000 ether);
        delegation.stake{value: 1_000_000 ether}();
        delegation.unstake(100_000 ether);
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
        vm.startPrank(owner);
        vm.deal(owner, owner.balance + 100000 ether);
        delegation.stake{value: 100000 ether}();
        delegation.unstake(100000 ether);
        vm.stopPrank();
        // control address stakes as much as the validator's deposit
        vm.startPrank(makeAddr("2"));
        uint256 amount =
            1_000_000_000 ether * (delegation.getDeposit(validator(2)) - delegation.getDelegatedAmount()) /
            (1_000_000_000 ether - 1_000_000_000 ether * delegation.getDeposit(validator(2)) / (delegation.getDeposit(validator(1)) + delegation.getDeposit(validator(2))));
        vm.deal(makeAddr("2"), makeAddr("2").balance + amount);
        delegation.stake{value: amount}();
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
        assertApproxEqAbs(withdrawnRewards1[0], withdrawnRewards2[2], 10, "withdrawn rewards mismatch");
        assertApproxEqAbs(withdrawnRewards1[1], withdrawnRewards2[3], 10, "withdrawn rewards mismatch");
    }

    function test_LeaveAfterOthersStakedNoPendingWithdrawalsNoRefund() public {
        uint256 depositAmount = 10_000_000 ether;
        addValidator(BaseDelegation(delegation), 2 * depositAmount, DepositMode.Bootstrapping);
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
        joinPool(BaseDelegation(delegation), depositAmount, makeAddr("2"), 2);
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
        address staker = stakers[4-1];
        // control address stakes as much as the validator's deposit
        vm.startPrank(makeAddr("2"));
        uint256 amount =
            1_000_000_000 ether * (delegation.getDeposit(validator(2)) - delegation.getDelegatedAmount()) /
            (1_000_000_000 ether - 1_000_000_000 ether * delegation.getDeposit(validator(2)) / (delegation.getDeposit(validator(1)) + delegation.getDeposit(validator(2))));
        vm.deal(makeAddr("2"), makeAddr("2").balance + amount);
        delegation.stake{value: amount}();
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
        assertApproxEqAbs(withdrawnRewards1[0], withdrawnRewards2[2], 10, "withdrawn rewards mismatch");
        assertApproxEqAbs(withdrawnRewards1[1], withdrawnRewards2[3], 10, "withdrawn rewards mismatch");
    }

    function test_DepositMultipleValidatorsFromPool() public {
        uint256 depositAmount = 10_000_000 ether;
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Fundraising);
        vm.deal(stakers[0], stakers[0].balance + 200 ether);
        vm.startPrank(stakers[0]);
        delegation.stake{value: 100 ether}();
        uint256 stakerBalance = stakers[0].balance;
        delegation.unstake(100 ether);
        vm.roll(block.number + delegation.unbondingPeriod());
        delegation.claim();
        assertEq(stakers[0].balance - stakerBalance, 100 ether, "balance mismatch after claiming");
        vm.stopPrank();
        depositFromPool(BaseDelegation(delegation), depositAmount, 2);
        vm.startPrank(stakers[0]);
        delegation.stake{value: 100 ether}();
        stakerBalance = stakers[0].balance;
        delegation.unstake(100 ether);
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
        delegation.unstake(delegation.getDelegatedAmount());
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
        stakers.push(owner);
        joinPool(BaseDelegation(delegation), depositAmount, makeAddr("2"), 2);
        stakers.push(makeAddr("2"));
        joinPool(BaseDelegation(delegation), depositAmount, makeAddr("3"), 3);
        stakers.push(makeAddr("3"));
        joinPool(BaseDelegation(delegation), depositAmount, makeAddr("4"), 4);
        stakers.push(makeAddr("4"));
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
        stakers.push(owner);
        joinPool(BaseDelegation(delegation), 2 * depositAmount, makeAddr("2"), 2);
        stakers.push(makeAddr("2"));
        joinPool(BaseDelegation(delegation), 2 * depositAmount, makeAddr("3"), 3);
        stakers.push(makeAddr("3"));
        joinPool(BaseDelegation(delegation), 2 * depositAmount, makeAddr("4"), 4);
        stakers.push(makeAddr("4"));
        joinPool(BaseDelegation(delegation), 2 * depositAmount, makeAddr("5"), 5);
        stakers.push(makeAddr("5"));
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
        delegation.unstake(20 * depositAmount / 10);
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
        delegation.unstake(20 * depositAmount / 10);
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
        delegation.unstake(15 * depositAmount / 10);
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
        delegation.unstake(20 * depositAmount / 10);
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
        delegation.unstake(5 * depositAmount / 10);
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

    function test_UndepositAllStakeAvailableForDepositFromPool() public {
        uint256 depositAmount = 10_000_000 ether;
        uint256 rewardAmount = 1_000_000 ether;
        addValidator(BaseDelegation(delegation), 2 * depositAmount, DepositMode.Bootstrapping);
        stakers.push(owner);
        vm.deal(address(delegation), address(delegation).balance + rewardAmount);
        joinPool(BaseDelegation(delegation), 2 * depositAmount, makeAddr("2"), 2);
        stakers.push(makeAddr("2"));
        joinPool(BaseDelegation(delegation), 2 * depositAmount, makeAddr("3"), 3);
        stakers.push(makeAddr("3"));
        joinPool(BaseDelegation(delegation), 2 * depositAmount, makeAddr("4"), 4);
        stakers.push(makeAddr("4"));
        joinPool(BaseDelegation(delegation), 2 * depositAmount, makeAddr("5"), 5);
        stakers.push(makeAddr("5"));
        vm.deal(address(delegation), address(delegation).balance + rewardAmount);
        vm.startPrank(makeAddr("5"));
        delegation.leavePool(validator(5));
        vm.stopPrank();
        vm.deal(address(delegation), address(delegation).balance + rewardAmount);
        assertEq(address(delegation).balance, 0 + 3 * rewardAmount - 2 * rewardAmount / 10, "incorrect balance");
        assertEq(delegation.getRewards(), 3 * rewardAmount - 2 * rewardAmount / 10, "incorrect rewards");
        assertEq(delegation.getStake(), 80 * depositAmount / 10, "incorrect stake");
        assertEq(delegation.validators().length, 4, "incorrect number of validators");
        assertEq(delegation.getDeposit(validator(1)), 20 * depositAmount / 10, "validator deposits are decreased equally");
        assertEq(delegation.getDeposit(validator(2)), 20 * depositAmount / 10, "validator deposits are decreased equally");
        assertEq(delegation.getDeposit(validator(3)), 20 * depositAmount / 10, "validator deposits are decreased equally");
        assertEq(delegation.getDeposit(validator(4)), 20 * depositAmount / 10, "validator deposits are decreased equally");
        vm.startPrank(makeAddr("2"));
        delegation.unstake(20 * depositAmount / 10);
        assertEq(delegation.getDeposit(validator(1)), 15 * depositAmount / 10, "validator deposits are decreased equally");
        assertEq(delegation.getDeposit(validator(2)), 15 * depositAmount / 10, "validator deposits are decreased equally");
        assertEq(delegation.getDeposit(validator(3)), 15 * depositAmount / 10, "validator deposits are decreased equally");
        assertEq(delegation.getDeposit(validator(4)), 15 * depositAmount / 10, "validator deposits are decreased equally");
        vm.roll(block.number + delegation.unbondingPeriod());
        uint256 balanceBefore = makeAddr("2").balance;
        delegation.claim();
        assertEq(makeAddr("2").balance - balanceBefore, 2 * depositAmount, "unstaked vs claimed amount mismatch");
        assertEq(address(delegation).balance, 0 + 3 * rewardAmount - 3 * rewardAmount / 10, "incorrect balance");
        assertEq(delegation.getRewards(), 3 * rewardAmount - 3 * rewardAmount / 10, "incorrect rewards");
        assertEq(delegation.getStake(), 60 * depositAmount / 10, "incorrect stake");
        assertEq(delegation.validators().length, 4, "incorrect number of validators");
        vm.stopPrank();
        vm.deal(address(delegation), address(delegation).balance + rewardAmount);
        vm.startPrank(makeAddr("3"));
        delegation.unstake(20 * depositAmount / 10);
        assertEq(delegation.getDeposit(validator(1)), 10 * depositAmount / 10, "validator deposits are decreased equally");
        assertEq(delegation.getDeposit(validator(2)), 10 * depositAmount / 10, "validator deposits are decreased equally");
        assertEq(delegation.getDeposit(validator(3)), 10 * depositAmount / 10, "validator deposits are decreased equally");
        assertEq(delegation.getDeposit(validator(4)), 10 * depositAmount / 10, "validator deposits are decreased equally");
        vm.roll(block.number + delegation.unbondingPeriod());
        balanceBefore = makeAddr("3").balance;
        delegation.claim();
        assertEq(makeAddr("3").balance - balanceBefore, 2 * depositAmount, "unstaked vs claimed amount mismatch");
        assertEq(address(delegation).balance, 0 + 4 * rewardAmount - 4 * rewardAmount / 10, "incorrect balance");
        assertEq(delegation.getRewards(), 4 * rewardAmount - 4 * rewardAmount / 10, "incorrect rewards");
        assertEq(delegation.getStake(), 40 * depositAmount / 10, "incorrect stake");
        assertEq(delegation.validators().length, 4, "incorrect number of validators");
        vm.stopPrank();
        vm.deal(address(delegation), address(delegation).balance + rewardAmount);
        vm.startPrank(makeAddr("4"));
        delegation.unstake(15 * depositAmount / 10);
        assertEq(address(delegation).balance, 0 + 5 * rewardAmount - 5 * rewardAmount / 10, "incorrect balance");
        assertEq(delegation.getRewards(), 5 * rewardAmount - 5 * rewardAmount / 10, "incorrect rewards");
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
        assertEq(address(delegation).balance, 0 + 5 * rewardAmount - 5 * rewardAmount / 10, "incorrect balance");
        assertEq(delegation.getRewards(), 5 * rewardAmount - 5 * rewardAmount / 10, "incorrect rewards");
        assertEq(delegation.getStake(), 25 * depositAmount / 10, "incorrect stake");
        assertEq(delegation.validators().length, 2, "incorrect number of validators");
        assertEq(delegation.getDeposit(validator(1)), 125 * depositAmount / 100, "validator deposit mismatch");
        assertEq(delegation.getDeposit(validator(2)), 125 * depositAmount / 100, "validator deposit mismatch");
        assertEq(delegation.getDeposit(validator(3)), 0, "validator deposit mismatch");
        assertEq(delegation.getDeposit(validator(4)), 0, "validator deposit mismatch");
        vm.stopPrank();
        vm.deal(address(delegation), address(delegation).balance + rewardAmount);
        vm.startPrank(owner);
        Console.log("-------------------------- after unstaking and claiming 15m of 4x 10m -> 12.5   12.5   0   0  + 0 balance");
        printStatus(delegation);
        delegation.unstake(20 * depositAmount / 10);
        assertEq(address(delegation).balance, 0 + 6 * rewardAmount - 6 * rewardAmount / 10, "incorrect balance");
        assertEq(delegation.getRewards(), 6 * rewardAmount - 6 * rewardAmount / 10, "incorrect rewards");
        assertEq(delegation.getStake(), 5 * depositAmount / 10, "incorrect stake");
        assertEq(delegation.validators().length, 2, "incorrect number of validators");
        assertEq(delegation.getDeposit(validator(1)), 0, "validator deposit mismatch"); // because FullyUndeposited
        assertEq(delegation.getDeposit(validator(2)), 0, "validator deposit mismatch");
        assertEq(delegation.getDeposit(validator(3)), 0, "validator deposit mismatch");
        assertEq(delegation.getDeposit(validator(4)), 0, "validator deposit mismatch");
        Console.log("-------------------------- after unstaking 20m of 2x 12.5m -> 0   0   0   0  + 5m balance");
        printStatus(delegation);
        vm.roll(block.number + delegation.unbondingPeriod());
        balanceBefore = owner.balance;
        delegation.claim();
        assertEq(owner.balance - balanceBefore, 20 * depositAmount / 10, "unstaked vs claimed amount mismatch");
        assertEq(address(delegation).balance, 5 * depositAmount / 10 + 6 * rewardAmount - 6 * rewardAmount / 10, "incorrect balance");
        assertEq(delegation.getRewards(), 6 * rewardAmount - 6 * rewardAmount / 10, "incorrect rewards");
        assertEq(delegation.getStake(), 5 * depositAmount / 10, "incorrect stake");
        assertEq(delegation.validators().length, 0, "incorrect number of validators");
        assertEq(delegation.getDeposit(validator(1)), 0, "validator deposit mismatch");
        assertEq(delegation.getDeposit(validator(2)), 0, "validator deposit mismatch");
        assertEq(delegation.getDeposit(validator(3)), 0, "validator deposit mismatch");
        assertEq(delegation.getDeposit(validator(4)), 0, "validator deposit mismatch");
        vm.stopPrank();
        vm.deal(address(delegation), address(delegation).balance + rewardAmount);
        vm.startPrank(makeAddr("4"));
        Console.log("-------------------------- after claiming the unstaked 20m");
        printStatus(delegation);
        delegation.unstake(2 * depositAmount / 10);
        Console.log("-------------------------- after unstaking 2m of 5m");
        printStatus(delegation);
        assertEq(address(delegation).balance, 5 * depositAmount / 10 + 7 * rewardAmount - 7 * rewardAmount / 10, "incorrect balance");
        assertEq(delegation.getRewards(), 7 * rewardAmount - 7 * rewardAmount / 10, "incorrect rewards");
        assertEq(delegation.getStake(), 3 * depositAmount / 10, "incorrect stake");
        assertEq(delegation.validators().length, 0, "incorrect number of validators");
        assertEq(delegation.getDeposit(validator(1)), 0, "validator deposit mismatch");
        assertEq(delegation.getDeposit(validator(2)), 0, "validator deposit mismatch");
        assertEq(delegation.getDeposit(validator(3)), 0, "validator deposit mismatch");
        assertEq(delegation.getDeposit(validator(4)), 0, "validator deposit mismatch");
        vm.roll(block.number + delegation.unbondingPeriod());
        balanceBefore = makeAddr("4").balance;
        delegation.claim();
        assertEq(makeAddr("4").balance - balanceBefore, 2 * depositAmount / 10, "unstaked vs claimed amount mismatch");
        assertEq(address(delegation).balance, 3 * depositAmount / 10 + 7 * rewardAmount - 7 * rewardAmount / 10, "incorrect balance");
        assertEq(delegation.getRewards(), 7 * rewardAmount - 7 * rewardAmount / 10, "incorrect rewards");
        assertEq(delegation.getStake(), 3 * depositAmount / 10, "incorrect stake");
        assertEq(delegation.validators().length, 0, "incorrect number of validators");
        assertEq(delegation.getDeposit(validator(1)), 0, "validator deposit mismatch");
        assertEq(delegation.getDeposit(validator(2)), 0, "validator deposit mismatch");
        assertEq(delegation.getDeposit(validator(3)), 0, "validator deposit mismatch");
        assertEq(delegation.getDeposit(validator(4)), 0, "validator deposit mismatch");
        vm.stopPrank();
        Console.log("-------------------------- after claiming the unstaked 2m");
        printStatus(delegation);
        vm.deal(address(delegation), address(delegation).balance + rewardAmount);
        depositFromPool(BaseDelegation(delegation), depositAmount - 3 * depositAmount / 10, 6);
        assertEq(address(delegation).balance, 0 + 8 * rewardAmount - 8 * rewardAmount / 10, "incorrect balance");
        assertEq(delegation.getRewards(), 8 * rewardAmount - 8 * rewardAmount / 10, "incorrect rewards");
        assertEq(delegation.getStake(), 10 * depositAmount / 10, "incorrect stake");
        assertEq(delegation.validators().length, 1, "incorrect number of validators");
        assertEq(delegation.getDeposit(validator(6)), 10 * depositAmount / 10, "validator deposit mismatch");
        assertEq(delegation.getDeposit(validator(1)), 0, "validator deposit mismatch");
        assertEq(delegation.getDeposit(validator(2)), 0, "validator deposit mismatch");
        assertEq(delegation.getDeposit(validator(3)), 0, "validator deposit mismatch");
        assertEq(delegation.getDeposit(validator(4)), 0, "validator deposit mismatch");
        Console.log("-------------------------- after depositing from pool");
        printStatus(delegation);
        vm.startPrank(makeAddr("4"));
        delegation.unstake(3 * depositAmount / 10);
        assertEq(address(delegation).balance, 0 + 8 * rewardAmount - 8 * rewardAmount / 10, "incorrect balance");
        assertEq(delegation.getRewards(), 8 * rewardAmount - 8 * rewardAmount / 10, "incorrect rewards");
        assertEq(delegation.getStake(), 7 * depositAmount / 10, "incorrect stake");
        assertEq(delegation.validators().length, 1, "incorrect number of validators");
        assertEq(delegation.getDeposit(validator(6)), 0, "validator deposit mismatch"); // because FullyUndeposited
        assertEq(delegation.getDeposit(validator(1)), 0, "validator deposit mismatch");
        assertEq(delegation.getDeposit(validator(2)), 0, "validator deposit mismatch");
        assertEq(delegation.getDeposit(validator(3)), 0, "validator deposit mismatch");
        assertEq(delegation.getDeposit(validator(4)), 0, "validator deposit mismatch");
        Console.log("-------------------------- after unstaking the remaining 3m");
        printStatus(delegation);
        vm.roll(block.number + delegation.unbondingPeriod());
        balanceBefore = makeAddr("4").balance;
        delegation.claim();
        assertEq(makeAddr("4").balance - balanceBefore, 3 * depositAmount / 10, "unstaked vs claimed amount mismatch");
        assertEq(address(delegation).balance, 7 * depositAmount / 10 + 8 * rewardAmount - 8 * rewardAmount / 10, "incorrect balance");
        assertEq(delegation.getRewards(), 8 * rewardAmount - 8 * rewardAmount / 10, "incorrect rewards");
        assertEq(delegation.getStake(), 7 * depositAmount / 10, "incorrect stake");
        assertEq(delegation.validators().length, 0, "incorrect number of validators");
        assertEq(delegation.getDeposit(validator(6)), 0, "validator deposit mismatch");
        assertEq(delegation.getDeposit(validator(1)), 0, "validator deposit mismatch");
        assertEq(delegation.getDeposit(validator(2)), 0, "validator deposit mismatch");
        assertEq(delegation.getDeposit(validator(3)), 0, "validator deposit mismatch");
        assertEq(delegation.getDeposit(validator(4)), 0, "validator deposit mismatch");
        Console.log("-------------------------- after claiming the unstaked 3m");
        printStatus(delegation);
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

    // run with
    // forge test -vv --via-ir --gas-report --gas-limit 10000000000 --block-gas-limit 10000000000 --match-test AfterMany
    function test_WithdrawAfterManyStakings() public {
        uint256 i;
        uint256 x;
        uint64 steps = 11_000;

        addValidator(BaseDelegation(delegation), 10_000_000 ether, DepositMode.Bootstrapping);

        // wait 2 epochs for the change to the deposit to take affect
        vm.roll(block.number + Deposit(delegation.DEPOSIT_CONTRACT()).blocksPerEpoch() * 2);

        for (i = 0; i < 4; i++) {
            vm.deal(stakers[i], 200_000 ether);
            Console.log("staker %s: %s", i+1, stakers[i]);
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
        //Console.log18("staker balance: %s.%s%s", stakers[i-1].balance);
        //uint256 rewards = delegation.rewards(steps);
        uint256 rewards = delegation.rewards();
        Console.log18("staker rewards: %s.%s%s", rewards);
        rewards = delegation.withdrawRewards(rewards, steps);
        //rewards = delegation.withdrawAllRewards();
        /*
        rewards = delegation.withdrawRewards(1000000, 2000);
        rewards += delegation.withdrawRewards(1000000, 2000);
        rewards += delegation.withdrawRewards(1000000, 2000);
        rewards += delegation.withdrawRewards(1000000, 2000);
        //*/
        Console.log18("staker withdrew: %s.%s%s", rewards);
        //Console.log18("staker balance: %s.%s%s", stakers[i-1].balance);
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

        addValidator(BaseDelegation(delegation), 10_000_000 ether, DepositMode.Bootstrapping);

        // wait 2 epochs for the change to the deposit to take affect
        vm.roll(block.number + Deposit(delegation.DEPOSIT_CONTRACT()).blocksPerEpoch() * 2);

        for (i = 0; i < 4; i++) {
            vm.deal(stakers[i], 200_000 ether);
            Console.log("staker %s: %s", i+1, stakers[i]);
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
        //Console.log18("staker balance: %s.%s%s", stakers[i-1].balance);
        //uint256 rewards = delegation.rewards(steps);
        uint256 rewards = delegation.rewards();
        Console.log18("staker rewards: %s.%s%s", rewards);
        rewards = delegation.withdrawRewards(rewards, steps);
        //rewards = delegation.withdrawAllRewards();
        /*
        rewards = delegation.withdrawRewards(1000000, 2000);
        rewards += delegation.withdrawRewards(1000000, 2000);
        rewards += delegation.withdrawRewards(1000000, 2000);
        rewards += delegation.withdrawRewards(1000000, 2000);
        //*/
        Console.log18("staker withdrew: %s.%s%s", rewards);
        //Console.log18("staker balance: %s.%s%s", stakers[i-1].balance);
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

        addValidator(BaseDelegation(delegation), 10_000_000 ether, DepositMode.Bootstrapping);

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
        Console.log("-----------------------------------------------");

        Console.log18("contract balance: %s.%s%s", address(delegation).balance);
        Console.log18("staker balance: %s.%s%s", stakers[i-1].balance);
        uint256 rewards = delegation.rewards();
        Console.log18("staker rewards: %s.%s%s", rewards);

        (
        uint64[] memory stakingIndices,
        uint64 firstPosInStakingIndices,
        uint256 availableTaxedRewards,
        uint64 lastWithdrawnRewardIndex,
        uint256 taxedSinceLastStaking
        ) = delegation.getStakingData();
        Console.log("stakingIndices = [ %s]", stakingIndices);
        Console.log("firstPosInStakingIndices = %s   lastWithdrawnRewardIndex = %s", uint256(firstPosInStakingIndices), uint256(lastWithdrawnRewardIndex));
        Console.log("availableTaxedRewards = %s   taxedSinceLastStaking = %s", availableTaxedRewards, taxedSinceLastStaking);

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
        firstPosInStakingIndices,
        availableTaxedRewards,
        lastWithdrawnRewardIndex,
        taxedSinceLastStaking
        ) = delegation.getStakingData();
        Console.log("stakingIndices = [ %s]", stakingIndices);
        Console.log("firstPosInStakingIndices = %s   lastWithdrawnRewardIndex = %s", uint256(firstPosInStakingIndices), uint256(lastWithdrawnRewardIndex));
        Console.log("availableTaxedRewards = %s   taxedSinceLastStaking = %s", availableTaxedRewards, taxedSinceLastStaking);

        Console.log18("contract balance: %s.%s%s", address(delegation).balance);
        Console.log18("staker balance: %s.%s%s", stakers[i-1].balance);
        Console.log18("staker rewards: %s.%s%s", delegation.rewards());
        Console.log18("staker should have received: %s.%s%s", rewards);
        vm.stopPrank();
    }

    function test_Fundraising_WithdrawAllRewardsThenNoMoreStakings() public {
        uint256 depositAmount = 10_000_000 ether;
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Fundraising);
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
        uint256 totalStakedZil;
        uint256 totalUnstakedZil;
        uint256 totalWithdrawnZil;
        uint256 totalEarnedZil;
        for (uint256 i = 0; i < numOfUsers; i++) {
            address user = vm.randomAddress();
            users.push(user);
            vm.deal(user, vm.randomUint(delegation.MIN_DELEGATION(), 100_000_000 ether));
        }
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
            // rewards are withdrawn in 30% of the operations
            if (operation % 3 == 0) {
                vm.startPrank(user);
                uint256 amount = delegation.withdrawAllRewards();
                vm.stopPrank();
                earnedZil[user] += amount;
                Console.log("%s withdrew %s and has earned %s rewards", user, amount, earnedZil[user]);
            }
            // staking is 10% of the operations attempted
            if (operation == 1) {
                if (user.balance < delegation.MIN_DELEGATION())
                    continue;
                Console.log("block %s avg rewards %s", block.number, rewards / blocks);
                uint256 amount = vm.randomUint(delegation.MIN_DELEGATION(), user.balance);
                uint256 totalStakeValue = delegation.getDelegatedTotal();
                vm.startPrank(user);
                delegation.stake{
                    value: amount
                }();
                vm.stopPrank();
                assertEq(totalStakeValue + amount, delegation.getDelegatedTotal(), "updated total stake value incorrect");
                stakedZil[user] += amount;
                totalStakedZil += amount;
                stakingsCounter++;
                Console.log("%s staked %s and has %s staked", user, amount, stakedZil[user]);
            }
            // unstaking is 40% of the operations attempted (20% full unstaking, 20% partial unstaking)
            if (operation >= 2 && operation <= 5) {
                if (stakedZil[user] == 0)
                    continue;
                Console.log("block %s avg rewards %s", block.number, rewards / blocks);
                uint256 amount =
                    operation % 2 == 0 && stakedZil[user] >= delegation.MIN_DELEGATION() ?
                    vm.randomUint(delegation.MIN_DELEGATION(), stakedZil[user]):
                    stakedZil[user];
                uint256 pendingBefore = delegation.totalPendingWithdrawals();
                uint256 totalStakeValue = delegation.getDelegatedTotal();
                vm.startPrank(user);
                amount = delegation.unstake(
                    amount
                );
                vm.stopPrank();
                assertEq(totalStakeValue - amount, delegation.getDelegatedTotal(), "updated total stake value incorrect");
                uint256 totalContribution = delegation.totalPendingWithdrawals() - pendingBefore;
                if (totalContribution < amount)
                    totalWithdrawnZil += amount - totalContribution;
                stakedZil[user] -= amount;
                totalStakedZil -= amount;
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
                Console.log("block %s avg rewards %s", block.number, rewards / blocks);
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
            assertEq(delegation.getStake(), delegation.getDelegatedTotal(), "getStake does not match getDelegatedTotal");
            assertEq(totalWithdrawnZil + delegation.totalPendingWithdrawals(), totalUnstakedZil, "owned does not match owed");
            assertLt(delegation.totalRoundingErrors(), numOfUsers * 1 ether, "rounding errors out of bounds");
        }
        uint256 outstandingRewards;
        uint256 totalDelegated;
        NonLiquidDelegation.Staking[] memory stakingHistory = delegation.getStakingHistory();
        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            vm.startPrank(user);
            uint256 userRewards = delegation.rewards();
            (uint64[] memory stakingIndices, , , , ) = delegation.getStakingData();
            vm.stopPrank();
            outstandingRewards += userRewards;
            //totalStakedZil += stakedZil[user];
            //totalUnstakedZil += unstakedZil[user];
            totalEarnedZil += earnedZil[user];
            if (stakingIndices.length > 0)
                totalDelegated += stakingHistory[stakingIndices[stakingIndices.length - 1]].amount;
            Console.log(stakedZil[user], unstakedZil[user], earnedZil[user], userRewards);
        }
        Console.log("%s total staked %s total unstaked %s total earned", totalStakedZil, totalUnstakedZil, totalEarnedZil);
        Console.log("%s stakings", stakingsCounter);
        Console.log("%s unstakings", unstakingsCounter);
        Console.log("%s claimings", claimingsCounter);
        assertEq(totalDelegated + depositAmount, delegation.getDelegatedTotal(), "sum of stakes does not match delegated total");
        // computing the outstanding rewards is expensive, therefore only once at the end
        assertLe(
            delegation.getDelegatedTotal() + outstandingRewards,
            delegation.getStake() + (delegation.getTaxedRewards() + (int256(delegation.getRewards()) - delegation.getTaxedRewards()) * int256(delegation.DENOMINATOR() - delegation.getCommissionNumerator()) / int256(delegation.DENOMINATOR())).toUint256(), 
            "exposure greater than funds"
        );
    }

    function test_CollectCommission() external {
        Console.log("------------------------------------- stake");
        addValidator(BaseDelegation(delegation), 10_000_000 ether, DepositMode.Bootstrapping);
        address staker = stakers[0];
        vm.deal(staker, staker.balance + 20_000_000 ether);
        vm.deal(owner, owner.balance + 10_000_000 ether);
        vm.startPrank(staker);
        delegation.stake{value: 10_000_000 ether}();
        vm.stopPrank();

        Console.log("------------------------------------- earn");
        vm.deal(address(delegation), address(delegation).balance + 100 ether);
        Console.log("total rewards:    %s", delegation.getRewards());
        Console.log("taxed rewards:    %s", delegation.getTaxedRewards());
        Console.log("taxed historical: %s", delegation.getHistoricalTaxedRewards());
        vm.startPrank(owner);
        Console.log("owner rewards:    %s", delegation.rewards());
        vm.stopPrank();
        vm.startPrank(staker);
        Console.log("staker rewards:   %s", delegation.rewards());
        vm.stopPrank();

        Console.log("------------------------------------- stake");
        vm.startPrank(owner);
        delegation.stake{value: 10_000_000 ether}();
        vm.stopPrank();
        vm.startPrank(staker);
        delegation.stake{value: 10_000_000 ether}();
        vm.stopPrank();
        Console.log("total rewards:    %s", delegation.getRewards());
        Console.log("taxed rewards:    %s", delegation.getTaxedRewards());
        Console.log("taxed historical: %s", delegation.getHistoricalTaxedRewards());
        vm.startPrank(owner);
        Console.log("owner rewards:    %s", delegation.rewards());
        vm.stopPrank();
        vm.startPrank(staker);
        Console.log("staker rewards:   %s", delegation.rewards());
        vm.stopPrank();

        Console.log("------------------------------------- earn");
        vm.deal(address(delegation), address(delegation).balance + 100 ether);
        Console.log("total rewards:    %s", delegation.getRewards());
        Console.log("taxed rewards:    %s", delegation.getTaxedRewards());
        Console.log("taxed historical: %s", delegation.getHistoricalTaxedRewards());
        vm.startPrank(owner);
        Console.log("owner rewards:    %s", delegation.rewards());
        vm.stopPrank();
        vm.startPrank(staker);
        Console.log("staker rewards:   %s", delegation.rewards());
        vm.stopPrank();

        Console.log("------------------------------------- collect");
        vm.startPrank(owner);
        delegation.collectCommission();
        vm.stopPrank();
        Console.log("total rewards:    %s", delegation.getRewards());
        Console.log("taxed rewards:    %s", delegation.getTaxedRewards());
        Console.log("taxed historical: %s", delegation.getHistoricalTaxedRewards());
        vm.startPrank(owner);
        Console.log("owner rewards:    %s", delegation.rewards());
        vm.stopPrank();
        vm.startPrank(staker);
        Console.log("staker rewards:   %s", delegation.rewards());
        vm.stopPrank();

        Console.log("------------------------------------- withdraw");
        vm.startPrank(owner);
        delegation.withdrawAllRewards();
        vm.stopPrank();
        vm.startPrank(staker);
        delegation.withdrawAllRewards();
        vm.stopPrank();
        Console.log("total rewards:    %s", delegation.getRewards());
        Console.log("taxed rewards:    %s", delegation.getTaxedRewards());
        Console.log("taxed historical: %s", delegation.getHistoricalTaxedRewards());
        vm.startPrank(owner);
        Console.log("owner rewards:    %s", delegation.rewards());
        vm.stopPrank();
        vm.startPrank(staker);
        Console.log("staker rewards:   %s", delegation.rewards());
        vm.stopPrank();

        Console.log("------------------------------------- earn");
        vm.deal(address(delegation), address(delegation).balance + 100 ether);
        Console.log("total rewards:    %s", delegation.getRewards());
        Console.log("taxed rewards:    %s", delegation.getTaxedRewards());
        Console.log("taxed historical: %s", delegation.getHistoricalTaxedRewards());
        vm.startPrank(owner);
        Console.log("owner rewards:    %s", delegation.rewards());
        vm.stopPrank();
        vm.startPrank(staker);
        Console.log("staker rewards:   %s", delegation.rewards());
        vm.stopPrank();

        Console.log("------------------------------------- withdraw");
        vm.startPrank(owner);
        delegation.withdrawAllRewards();
        vm.stopPrank();
        vm.startPrank(staker);
        delegation.withdrawAllRewards();
        vm.stopPrank();
        Console.log("total rewards:    %s", delegation.getRewards());
        Console.log("taxed rewards:    %s", delegation.getTaxedRewards());
        Console.log("taxed historical: %s", delegation.getHistoricalTaxedRewards());
        vm.startPrank(owner);
        Console.log("owner rewards:    %s", delegation.rewards());
        vm.stopPrank();
        vm.startPrank(staker);
        Console.log("staker rewards:   %s", delegation.rewards());
        vm.stopPrank();

        Console.log("------------------------------------- collect");
        vm.startPrank(owner);
        delegation.collectCommission();
        vm.stopPrank();
        Console.log("total rewards:    %s", delegation.getRewards());
        Console.log("taxed rewards:    %s", delegation.getTaxedRewards());
        Console.log("taxed historical: %s", delegation.getHistoricalTaxedRewards());
        vm.startPrank(owner);
        Console.log("owner rewards:    %s", delegation.rewards());
        vm.stopPrank();
        vm.startPrank(staker);
        Console.log("staker rewards:   %s", delegation.rewards());
        vm.stopPrank();

        Console.log("------------------------------------- collect");
        vm.startPrank(owner);
        delegation.collectCommission();
        vm.stopPrank();
        Console.log("total rewards:    %s", delegation.getRewards());
        Console.log("taxed rewards:    %s", delegation.getTaxedRewards());
        Console.log("taxed historical: %s", delegation.getHistoricalTaxedRewards());
        vm.startPrank(owner);
        Console.log("owner rewards:    %s", delegation.rewards());
        vm.stopPrank();
        vm.startPrank(staker);
        Console.log("staker rewards:   %s", delegation.rewards());
        vm.stopPrank();

        Console.log("------------------------------------- withdraw");
        vm.startPrank(owner);
        delegation.withdrawAllRewards();
        vm.stopPrank();
        vm.startPrank(staker);
        delegation.withdrawAllRewards();
        vm.stopPrank();
        Console.log("total rewards:    %s", delegation.getRewards());
        Console.log("taxed rewards:    %s", delegation.getTaxedRewards());
        Console.log("taxed historical: %s", delegation.getHistoricalTaxedRewards());
        vm.startPrank(owner);
        Console.log("owner rewards:    %s", delegation.rewards());
        vm.stopPrank();
        vm.startPrank(staker);
        Console.log("staker rewards:   %s", delegation.rewards());
        vm.stopPrank();
    }

    function test_rewardsWhenAllUnstaked_WithdrawNoRewards() public {
        uint256 depositAmount = 10_000_000 ether;
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        vm.deal(address(delegation), address(delegation).balance + 1000 ether);
        vm.startPrank(owner);
        delegation.withdrawAllRewards();
        vm.stopPrank();
        uint256 withdrawn;
        address staker = stakers[0];
        vm.deal(staker, staker.balance + 2 * depositAmount);
        vm.startPrank(staker);
        delegation.stake{value: depositAmount}();
        assertEq(2 * delegation.getDelegatedAmount(), delegation.getDelegatedTotal(), "delegated amount must be half of the total delegated");
        vm.deal(address(delegation), address(delegation).balance + 1000 ether);
        assertEq(delegation.rewards() + withdrawn, 500 ether * (delegation.DENOMINATOR() - delegation.getCommissionNumerator()) / delegation.DENOMINATOR(), "incorrect reward amount");
        vm.deal(address(delegation), address(delegation).balance + 1000 ether);
        delegation.unstake(delegation.getDelegatedAmount());
        assertEq(delegation.getDelegatedAmount(), 0, "delegated amount must be zero");
        assertEq(delegation.rewards() + withdrawn, 1000 ether * (delegation.DENOMINATOR() - delegation.getCommissionNumerator()) / delegation.DENOMINATOR(), "incorrect reward amount");
        vm.stopPrank();
        vm.deal(owner, owner.balance + 3 * depositAmount);
        vm.startPrank(owner);
        for (uint256 i = 0; i < 10; i++) {
            vm.deal(address(delegation), address(delegation).balance + 1000 ether);
            delegation.stake{value: depositAmount / 10}();
        }
        for (uint256 i = 0; i < 10; i++) {
            vm.deal(address(delegation), address(delegation).balance + 1000 ether);
            delegation.unstake(depositAmount / 10);
        }
        vm.stopPrank();        
        vm.startPrank(staker);
        vm.deal(address(delegation), address(delegation).balance + 1000 ether);
        assertEq(delegation.rewards() + withdrawn, 1000 ether * (delegation.DENOMINATOR() - delegation.getCommissionNumerator()) / delegation.DENOMINATOR(), "incorrect reward amount");
        delegation.stake{value: depositAmount}();
        assertEq(2 * delegation.getDelegatedAmount(), delegation.getDelegatedTotal(), "delegated amount must be half of the total delegated");
        vm.deal(address(delegation), address(delegation).balance + 1000 ether);
        assertEq(delegation.rewards() + withdrawn, 1500 ether * (delegation.DENOMINATOR() - delegation.getCommissionNumerator()) / delegation.DENOMINATOR(), "incorrect reward amount");
        vm.deal(address(delegation), address(delegation).balance + 1000 ether);
        delegation.unstake(delegation.getDelegatedAmount());
        vm.deal(address(delegation), address(delegation).balance + 1000 ether);
        vm.stopPrank();
        vm.startPrank(owner);
        delegation.stake{value: depositAmount}();
        vm.stopPrank();        
        vm.startPrank(staker);
        vm.deal(address(delegation), address(delegation).balance + 1000 ether);
        assertEq(delegation.rewards() + withdrawn, 2000 ether * (delegation.DENOMINATOR() - delegation.getCommissionNumerator()) / delegation.DENOMINATOR(), "incorrect reward amount");
        // additional steps = all steps - 1 where all steps = staker staked and unstaked, owner staked 10 times and unstaked 10 times, staker staked and unstaked, owner staked
        // thereof withdrawn: 0
        assertEq(delegation.getAdditionalSteps(), 1 + 10 + 10 + 1 + 1 + 1, "incorrect number of additional steps");
        withdrawn += delegation.withdrawAllRewards();
        assertEq(delegation.rewards() + withdrawn, 2000 ether * (delegation.DENOMINATOR() - delegation.getCommissionNumerator()) / delegation.DENOMINATOR(), "incorrect reward amount");
        assertEq(delegation.getAdditionalSteps(), 0, "incorrect number of additional steps");
        vm.stopPrank();
    }

    function test_rewardsWhenAllUnstaked_WithdrawAllRewards() public {
        uint256 depositAmount = 10_000_000 ether;
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        vm.deal(address(delegation), address(delegation).balance + 1000 ether);
        vm.startPrank(owner);
        delegation.withdrawAllRewards();
        vm.stopPrank();
        uint256 withdrawn;
        address staker = stakers[0];
        vm.deal(staker, staker.balance + 2 * depositAmount);
        vm.startPrank(staker);
        delegation.stake{value: depositAmount}();
        assertEq(2 * delegation.getDelegatedAmount(), delegation.getDelegatedTotal(), "delegated amount must be half of the total delegated");
        vm.deal(address(delegation), address(delegation).balance + 1000 ether);
        assertEq(delegation.rewards() + withdrawn, 500 ether * (delegation.DENOMINATOR() - delegation.getCommissionNumerator()) / delegation.DENOMINATOR(), "incorrect reward amount");
        vm.deal(address(delegation), address(delegation).balance + 1000 ether);
        delegation.unstake(delegation.getDelegatedAmount());
        assertEq(delegation.getDelegatedAmount(), 0, "delegated amount must be zero");
        assertEq(delegation.rewards() + withdrawn, 1000 ether * (delegation.DENOMINATOR() - delegation.getCommissionNumerator()) / delegation.DENOMINATOR(), "incorrect reward amount");
        vm.stopPrank();
        vm.deal(owner, owner.balance + 3 * depositAmount);
        vm.startPrank(owner);
        for (uint256 i = 0; i < 10; i++) {
            vm.deal(address(delegation), address(delegation).balance + 1000 ether);
            delegation.stake{value: depositAmount / 10}();
        }
        for (uint256 i = 0; i < 10; i++) {
            vm.deal(address(delegation), address(delegation).balance + 1000 ether);
            delegation.unstake(depositAmount / 10);
        }
        vm.stopPrank();        
        vm.startPrank(staker);
        vm.deal(address(delegation), address(delegation).balance + 1000 ether);
        withdrawn += delegation.withdrawAllRewards();
        vm.deal(address(delegation), address(delegation).balance + 1000 ether);
        assertEq(delegation.rewards() + withdrawn, 1000 ether * (delegation.DENOMINATOR() - delegation.getCommissionNumerator()) / delegation.DENOMINATOR(), "incorrect reward amount");
        delegation.stake{value: depositAmount}();
        assertEq(2 * delegation.getDelegatedAmount(), delegation.getDelegatedTotal(), "delegated amount must be half of the total delegated");
        vm.deal(address(delegation), address(delegation).balance + 1000 ether);
        assertEq(delegation.rewards() + withdrawn, 1500 ether * (delegation.DENOMINATOR() - delegation.getCommissionNumerator()) / delegation.DENOMINATOR(), "incorrect reward amount");
        vm.deal(address(delegation), address(delegation).balance + 1000 ether);
        delegation.unstake(delegation.getDelegatedAmount());
        vm.deal(address(delegation), address(delegation).balance + 1000 ether);
        vm.stopPrank();
        vm.startPrank(owner);
        delegation.stake{value: depositAmount}();
        vm.stopPrank();        
        vm.startPrank(staker);
        vm.deal(address(delegation), address(delegation).balance + 1000 ether);
        assertEq(delegation.rewards() + withdrawn, 2000 ether * (delegation.DENOMINATOR() - delegation.getCommissionNumerator()) / delegation.DENOMINATOR(), "incorrect reward amount");
        // additional steps = all steps - 1 where all steps = staker staked and unstaked, owner staked 10 times and unstaked 10 times, staker staked and unstaked, owner staked
        // thereof withdrawn: everything until withdrawAllRewards() was called, i.e. everything but the last time when staker staked and unstaked and the owner staked
        assertEq(delegation.getAdditionalSteps() + 1 + 10 + 10, 1 + 10 + 10 + 1 + 1 + 1, "incorrect number of additional steps");
        withdrawn += delegation.withdrawAllRewards();
        assertEq(delegation.rewards() + withdrawn, 2000 ether * (delegation.DENOMINATOR() - delegation.getCommissionNumerator()) / delegation.DENOMINATOR(), "incorrect reward amount");
        assertEq(delegation.getAdditionalSteps(), 0, "incorrect number of additional steps");
        vm.stopPrank();
    }

    function test_rewardsWhenAllUnstaked_WithdrawSpecifiedAmount() public {
        uint256 depositAmount = 10_000_000 ether;
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        vm.deal(address(delegation), address(delegation).balance + 1000 ether);
        vm.startPrank(owner);
        delegation.withdrawAllRewards();
        vm.stopPrank();
        uint256 withdrawn;
        address staker = stakers[0];
        vm.deal(staker, staker.balance + 2 * depositAmount);
        vm.startPrank(staker);
        delegation.stake{value: depositAmount}();
        assertEq(2 * delegation.getDelegatedAmount(), delegation.getDelegatedTotal(), "delegated amount must be half of the total delegated");
        vm.deal(address(delegation), address(delegation).balance + 1000 ether);
        assertEq(delegation.rewards() + withdrawn, 500 ether * (delegation.DENOMINATOR() - delegation.getCommissionNumerator()) / delegation.DENOMINATOR(), "incorrect reward amount");
        vm.deal(address(delegation), address(delegation).balance + 1000 ether);
        delegation.unstake(delegation.getDelegatedAmount());
        assertEq(delegation.getDelegatedAmount(), 0, "delegated amount must be zero");
        assertEq(delegation.rewards() + withdrawn, 1000 ether * (delegation.DENOMINATOR() - delegation.getCommissionNumerator()) / delegation.DENOMINATOR(), "incorrect reward amount");
        vm.stopPrank();
        vm.deal(owner, owner.balance + 3 * depositAmount);
        vm.startPrank(owner);
        for (uint256 i = 0; i < 10; i++) {
            vm.deal(address(delegation), address(delegation).balance + 1000 ether);
            delegation.stake{value: depositAmount / 10}();
        }
        for (uint256 i = 0; i < 10; i++) {
            vm.deal(address(delegation), address(delegation).balance + 1000 ether);
            delegation.unstake(depositAmount / 10);
        }
        vm.stopPrank();        
        vm.startPrank(staker);
        vm.deal(address(delegation), address(delegation).balance + 1000 ether);
        withdrawn += delegation.withdrawRewards(800 ether);
        vm.deal(address(delegation), address(delegation).balance + 1000 ether);
        assertEq(delegation.rewards() + withdrawn, 1000 ether * (delegation.DENOMINATOR() - delegation.getCommissionNumerator()) / delegation.DENOMINATOR(), "incorrect reward amount");
        delegation.stake{value: depositAmount}();
        assertEq(2 * delegation.getDelegatedAmount(), delegation.getDelegatedTotal(), "delegated amount must be half of the total delegated");
        vm.deal(address(delegation), address(delegation).balance + 1000 ether);
        assertEq(delegation.rewards() + withdrawn, 1500 ether * (delegation.DENOMINATOR() - delegation.getCommissionNumerator()) / delegation.DENOMINATOR(), "incorrect reward amount");
        vm.deal(address(delegation), address(delegation).balance + 1000 ether);
        delegation.unstake(delegation.getDelegatedAmount());
        vm.deal(address(delegation), address(delegation).balance + 1000 ether);
        vm.stopPrank();
        vm.startPrank(owner);
        delegation.stake{value: depositAmount}();
        vm.stopPrank();        
        vm.startPrank(staker);
        vm.deal(address(delegation), address(delegation).balance + 1000 ether);
        assertEq(delegation.rewards() + withdrawn, 2000 ether * (delegation.DENOMINATOR() - delegation.getCommissionNumerator()) / delegation.DENOMINATOR(), "incorrect reward amount");
        // additional steps = all steps - 1 where all steps = staker staked and unstaked, owner staked 10 times and unstaked 10 times, staker staked and unstaked, owner staked
        // thereof withdrawn: everything until withdrawAllRewards() was called, i.e. everything but the last time when staker staked and unstaked and the owner staked
        assertEq(delegation.getAdditionalSteps() + 1 + 10 + 10, 1 + 10 + 10 + 1 + 1 + 1, "incorrect number of additional steps");
        withdrawn += delegation.withdrawAllRewards();
        assertEq(delegation.rewards() + withdrawn, 2000 ether * (delegation.DENOMINATOR() - delegation.getCommissionNumerator()) / delegation.DENOMINATOR(), "incorrect reward amount");
        assertEq(delegation.getAdditionalSteps(), 0, "incorrect number of additional steps");
        vm.stopPrank();
    }

    function test_rewardsWhenAllUnstaked_WithdrawSpecifiedSteps() public {
        uint256 depositAmount = 10_000_000 ether;
        uint64 additionalSteps = 25;
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        vm.deal(address(delegation), address(delegation).balance + 1000 ether);
        vm.startPrank(owner);
        delegation.withdrawAllRewards();
        vm.stopPrank();
        uint256 withdrawn;
        address staker = stakers[0];
        vm.deal(staker, staker.balance + 2 * depositAmount);
        vm.startPrank(staker);
        delegation.stake{value: depositAmount}();
        assertEq(2 * delegation.getDelegatedAmount(), delegation.getDelegatedTotal(), "delegated amount must be half of the total delegated");
        vm.deal(address(delegation), address(delegation).balance + 1000 ether);
        assertEq(delegation.rewards() + withdrawn, 500 ether * (delegation.DENOMINATOR() - delegation.getCommissionNumerator()) / delegation.DENOMINATOR(), "incorrect reward amount");
        vm.deal(address(delegation), address(delegation).balance + 1000 ether);
        delegation.unstake(delegation.getDelegatedAmount());
        assertEq(delegation.getDelegatedAmount(), 0, "delegated amount must be zero");
        assertEq(delegation.rewards() + withdrawn, 1000 ether * (delegation.DENOMINATOR() - delegation.getCommissionNumerator()) / delegation.DENOMINATOR(), "incorrect reward amount");
        vm.stopPrank();
        vm.deal(owner, owner.balance + 3 * depositAmount);
        vm.startPrank(owner);
        for (uint256 i = 0; i < 10; i++) {
            vm.deal(address(delegation), address(delegation).balance + 1000 ether);
            delegation.stake{value: depositAmount / 10}();
        }
        for (uint256 i = 0; i < 10; i++) {
            vm.deal(address(delegation), address(delegation).balance + 1000 ether);
            delegation.unstake(depositAmount / 10);
        }
        vm.stopPrank();        
        vm.startPrank(staker);
        vm.deal(address(delegation), address(delegation).balance + 1000 ether);
        withdrawn += delegation.withdrawAllRewards(additionalSteps);
        vm.deal(address(delegation), address(delegation).balance + 1000 ether);
        assertEq(delegation.rewards() + withdrawn, 1000 ether * (delegation.DENOMINATOR() - delegation.getCommissionNumerator()) / delegation.DENOMINATOR(), "incorrect reward amount");
        delegation.stake{value: depositAmount}();
        assertEq(2 * delegation.getDelegatedAmount(), delegation.getDelegatedTotal(), "delegated amount must be half of the total delegated");
        vm.deal(address(delegation), address(delegation).balance + 1000 ether);
        assertEq(delegation.rewards() + withdrawn, 1500 ether * (delegation.DENOMINATOR() - delegation.getCommissionNumerator()) / delegation.DENOMINATOR(), "incorrect reward amount");
        vm.deal(address(delegation), address(delegation).balance + 1000 ether);
        delegation.unstake(delegation.getDelegatedAmount());
        vm.deal(address(delegation), address(delegation).balance + 1000 ether);
        vm.stopPrank();
        vm.startPrank(owner);
        delegation.stake{value: depositAmount}();
        vm.stopPrank();        
        vm.startPrank(staker);
        vm.deal(address(delegation), address(delegation).balance + 1000 ether);
        assertEq(delegation.rewards() + withdrawn, 2000 ether * (delegation.DENOMINATOR() - delegation.getCommissionNumerator()) / delegation.DENOMINATOR(), "incorrect reward amount");
        // additional steps = all steps - 1 where all steps = staker staked and unstaked, owner staked 10 times and unstaked 10 times, staker staked and unstaked, owner staked
        // if we withdrew any additional step, we also skipped all steps that had existed at that point i.e. staker unstaked, owner staked 10 times and unstaked 10 times
        // because the first additional step rendered a zero amount and there was no other staking by the staker
        if (additionalSteps > 0)
            additionalSteps = 1 + 10 + 10;
        assertEq(delegation.getAdditionalSteps() + additionalSteps, 1 + 10 + 10 + 1 + 1 + 1, "incorrect number of additional steps");
        withdrawn += delegation.withdrawAllRewards();
        assertEq(delegation.rewards() + withdrawn, 2000 ether * (delegation.DENOMINATOR() - delegation.getCommissionNumerator()) / delegation.DENOMINATOR(), "incorrect reward amount");
        assertEq(delegation.getAdditionalSteps(), 0, "incorrect number of additional steps");
        vm.stopPrank();
    }

    function test_rewardsWhenAllUnstaked_WithdrawSpecifiedAmountAndSteps() public {
        uint256 depositAmount = 10_000_000 ether;
        uint64 additionalSteps = 10;
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        vm.deal(address(delegation), address(delegation).balance + 1000 ether);
        vm.startPrank(owner);
        delegation.withdrawAllRewards();
        vm.stopPrank();
        uint256 withdrawn;
        address staker = stakers[0];
        vm.deal(staker, staker.balance + 2 * depositAmount);
        vm.startPrank(staker);
        delegation.stake{value: depositAmount}();
        assertEq(2 * delegation.getDelegatedAmount(), delegation.getDelegatedTotal(), "delegated amount must be half of the total delegated");
        vm.deal(address(delegation), address(delegation).balance + 1000 ether);
        assertEq(delegation.rewards() + withdrawn, 500 ether * (delegation.DENOMINATOR() - delegation.getCommissionNumerator()) / delegation.DENOMINATOR(), "incorrect reward amount");
        vm.deal(address(delegation), address(delegation).balance + 1000 ether);
        delegation.unstake(delegation.getDelegatedAmount());
        assertEq(delegation.getDelegatedAmount(), 0, "delegated amount must be zero");
        assertEq(delegation.rewards() + withdrawn, 1000 ether * (delegation.DENOMINATOR() - delegation.getCommissionNumerator()) / delegation.DENOMINATOR(), "incorrect reward amount");
        vm.stopPrank();
        vm.deal(owner, owner.balance + 3 * depositAmount);
        vm.startPrank(owner);
        for (uint256 i = 0; i < 10; i++) {
            vm.deal(address(delegation), address(delegation).balance + 1000 ether);
            delegation.stake{value: depositAmount / 10}();
        }
        for (uint256 i = 0; i < 10; i++) {
            vm.deal(address(delegation), address(delegation).balance + 1000 ether);
            delegation.unstake(depositAmount / 10);
        }
        vm.stopPrank();        
        vm.startPrank(staker);
        vm.deal(address(delegation), address(delegation).balance + 1000 ether);
        withdrawn += delegation.withdrawRewards(800 ether, additionalSteps);
        vm.deal(address(delegation), address(delegation).balance + 1000 ether);
        assertEq(delegation.rewards() + withdrawn, 1000 ether * (delegation.DENOMINATOR() - delegation.getCommissionNumerator()) / delegation.DENOMINATOR(), "incorrect reward amount");
        delegation.stake{value: depositAmount}();
        assertEq(2 * delegation.getDelegatedAmount(), delegation.getDelegatedTotal(), "delegated amount must be half of the total delegated");
        vm.deal(address(delegation), address(delegation).balance + 1000 ether);
        assertEq(delegation.rewards() + withdrawn, 1500 ether * (delegation.DENOMINATOR() - delegation.getCommissionNumerator()) / delegation.DENOMINATOR(), "incorrect reward amount");
        vm.deal(address(delegation), address(delegation).balance + 1000 ether);
        delegation.unstake(delegation.getDelegatedAmount());
        vm.deal(address(delegation), address(delegation).balance + 1000 ether);
        vm.stopPrank();
        vm.startPrank(owner);
        delegation.stake{value: depositAmount}();
        vm.stopPrank();        
        vm.startPrank(staker);
        vm.deal(address(delegation), address(delegation).balance + 1000 ether);
        assertEq(delegation.rewards() + withdrawn, 2000 ether * (delegation.DENOMINATOR() - delegation.getCommissionNumerator()) / delegation.DENOMINATOR(), "incorrect reward amount");
        // additional steps = all steps - 1 where all steps = staker staked and unstaked, owner staked 10 times and unstaked 10 times, staker staked and unstaked, owner staked
        // if we withdrew any additional step, we also skipped all steps that had existed at that point i.e. staked unstaked, owner staked 10 times and unstaked 10 times
        // because the first additional step rendered a zero amount and there was no other staking by the staker
        if (additionalSteps > 0)
            additionalSteps = 1 + 10 + 10;
        assertEq(delegation.getAdditionalSteps() + additionalSteps, 1 + 10 + 10 + 1 + 1 + 1, "incorrect number of additional steps");
        withdrawn += delegation.withdrawAllRewards();
        assertEq(delegation.rewards() + withdrawn, 2000 ether * (delegation.DENOMINATOR() - delegation.getCommissionNumerator()) / delegation.DENOMINATOR(), "incorrect reward amount");
        assertEq(delegation.getAdditionalSteps(), 0, "incorrect number of additional steps");
        vm.stopPrank();
    }

    function test_withdrawAllRewardsVsMaxAdditionalSteps() public {
        uint256 depositAmount = 10_000_000 ether;
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        vm.deal(owner, owner.balance + 10 * depositAmount);
        vm.startPrank(owner);
        //vm.deal(address(delegation), address(delegation).balance + 1000 ether);
        //delegation.withdrawAllRewards();
        for (uint256 i = 0; i < 10; i++) {
            vm.deal(address(delegation), address(delegation).balance + 1000 ether);
            delegation.stake{value: depositAmount / 10}();
        }
        vm.deal(address(delegation), address(delegation).balance + 1000 ether);
        assertEq(
            delegation.rewards(delegation.getAdditionalSteps()), 
            delegation.rewards(), 
            "reward amount mismatch"
        );
        assertEq(
            delegation.withdrawAllRewards(delegation.getAdditionalSteps()), 
            11 * 1000 ether * (delegation.DENOMINATOR() - delegation.getCommissionNumerator()) / delegation.DENOMINATOR(),
            "incorrect reward amount"
        );
        assertEq(delegation.getAdditionalSteps(), 0, "incorrect number of additional steps");
        assertEq(
            delegation.withdrawAllRewards(), 
            0, 
            "incorrect reward amount"
        );
        vm.stopPrank();
    }

    function test_TooManyValidators() public {
        uint256 depositAmount = 10_000_000 ether;
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        stakers.push(owner);
        for (uint256 i = 2; i <= delegation.MAX_VALIDATORS(); i++) {
            joinPool(BaseDelegation(delegation), depositAmount, makeAddr(Strings.toString(i)), uint8(i));
            stakers.push(makeAddr(Strings.toString(i)));
        }
        address staker = stakers[0];
        vm.deal(staker, staker.balance + 1000 ether);
        vm.startPrank(staker);
        Console.log("pooled stake: %s", delegation.getStake());
        delegation.stake{value: 1000 ether}();
        Console.log("pooled stake: %s", delegation.getStake());
        delegation.unstake(100 ether);
        Console.log("pooled stake: %s", delegation.getStake());
        vm.roll(block.number + delegation.unbondingPeriod());
        delegation.claim();
        vm.stopPrank();
    }

    function test_NotManyValidators() public {
        uint256 depositAmount = 10_000_000 ether;
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        stakers.push(owner);
        for (uint256 i = 2; i < 16; i++) {
            joinPool(BaseDelegation(delegation), depositAmount, makeAddr(Strings.toString(i)), uint8(i));
            stakers.push(makeAddr(Strings.toString(i)));
        }
        address staker = stakers[0];
        vm.deal(staker, staker.balance + 1000 ether);
        vm.startPrank(staker);
        Console.log("pooled stake: %s", delegation.getStake());
        delegation.stake{value: 1000 ether}();
        Console.log("pooled stake: %s", delegation.getStake());
        delegation.unstake(100 ether);
        Console.log("pooled stake: %s", delegation.getStake());
        vm.roll(block.number + delegation.unbondingPeriod());
        delegation.claim();
        vm.stopPrank();
    }

    function test_CommissionChangeTooEarly() public {
        uint256 depositAmount = 10_000_000 ether;
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        address staker = stakers[0];
        vm.deal(staker, staker.balance + 1000 ether);
        vm.startPrank(staker);
        delegation.stake{value: 1000 ether}();
        vm.stopPrank();
        vm.startPrank(owner);
        vm.roll(block.number + delegation.DELAY());
        delegation.setCommissionNumerator(900);
        vm.roll(block.number + delegation.DELAY() - 1);
        vm.expectRevert();
        delegation.setCommissionNumerator(800);
        vm.stopPrank();
    }

    function test_CommissionChangeTooFast() public {
        uint256 depositAmount = 10_000_000 ether;
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        address staker = stakers[0];
        vm.deal(staker, staker.balance + 1000 ether);
        vm.startPrank(staker);
        delegation.stake{value: 1000 ether}();
        vm.stopPrank();
        vm.startPrank(owner);
        vm.roll(block.number + delegation.DELAY());
        vm.expectRevert();
        delegation.setCommissionNumerator(800);
        vm.stopPrank();
    }

    function test_CommissionChangeTooEarly_NoStakeLeft() public {
        uint256 depositAmount = 10_000_000 ether;
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        addValidator(BaseDelegation(delegations[0]), depositAmount, DepositMode.Bootstrapping);
        address staker = stakers[0];
        vm.deal(staker, staker.balance + 1000 ether);
        vm.startPrank(staker);
        delegation.stake{value: 1000 ether}();
        delegation.unstake(delegation.getDelegatedAmount());
        delegation.withdrawAllRewards();
        vm.stopPrank();
        vm.startPrank(owner);
        delegation.unstake(delegation.getDelegatedAmount());
        assertEq(delegation.getStake(), 0, "there must be no stake");
        vm.roll(block.number + delegation.DELAY());
        delegation.setCommissionNumerator(900);
        vm.roll(block.number + delegation.DELAY() - 1);
        delegation.setCommissionNumerator(800);
        vm.stopPrank();
    }

    function test_CommissionChangeTooFast_NoStakeLeft() public {
        uint256 depositAmount = 10_000_000 ether;
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        addValidator(BaseDelegation(delegations[0]), depositAmount, DepositMode.Bootstrapping);
        address staker = stakers[0];
        vm.deal(staker, staker.balance + 1000 ether);
        vm.startPrank(staker);
        delegation.stake{value: 1000 ether}();
        delegation.unstake(delegation.getDelegatedAmount());
        delegation.withdrawAllRewards();
        vm.stopPrank();
        vm.startPrank(owner);
        delegation.unstake(delegation.getDelegatedAmount());
        assertEq(delegation.getStake(), 0, "there must be no stake");
        vm.roll(block.number + delegation.DELAY());
        delegation.setCommissionNumerator(800);
        vm.stopPrank();
    }

    function test_CommissionChangeTooEarly_NoStakeYet() public {
        vm.startPrank(owner);
        assertEq(delegation.getStake(), 0, "there must be no stake");
        vm.roll(block.number + delegation.DELAY());
        delegation.setCommissionNumerator(900);
        vm.roll(block.number + delegation.DELAY() - 1);
        delegation.setCommissionNumerator(800);
        vm.stopPrank();
    }

    function test_CommissionChangeTooFast_NoStakeYet() public {
        vm.startPrank(owner);
        assertEq(delegation.getStake(), 0, "there must be no stake");
        vm.roll(block.number + delegation.DELAY());
        delegation.setCommissionNumerator(800);
        vm.stopPrank();
    }

    function test_CommissionChangeTooEarly_NotActivated() public {
        address staker = stakers[0];
        vm.deal(staker, staker.balance + 1000 ether);
        vm.startPrank(staker);
        delegation.stake{value: 1000 ether}();
        vm.stopPrank();
        vm.startPrank(owner);
        vm.roll(block.number + delegation.DELAY());
        delegation.setCommissionNumerator(900);
        vm.roll(block.number + delegation.DELAY() - 1);
        vm.expectRevert();
        delegation.setCommissionNumerator(800);
        vm.stopPrank();
    }

    function test_CommissionChangeTooFast_NotActivated() public {
        address staker = stakers[0];
        vm.deal(staker, staker.balance + 1000 ether);
        vm.startPrank(staker);
        delegation.stake{value: 1000 ether}();
        vm.stopPrank();
        vm.startPrank(owner);
        vm.roll(block.number + delegation.DELAY());
        vm.expectRevert();
        delegation.setCommissionNumerator(800);
        vm.stopPrank();
    }

    function test_BlowUpStakingHistory() public {
        uint256 depositAmount = 10_000_000 ether;
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        vm.deal(address(delegation), 50_000 ether);
        address attacker = stakers[0];
        address staker = stakers[1];
        vm.deal(staker, 10_000 ether);
        vm.startPrank(staker);
        delegation.stake{value: 10_000 ether}();
        vm.stopPrank();
        vm.deal(attacker, 20_000 * delegation.MIN_DELEGATION());
        vm.startPrank(attacker);
        for (uint256 i = 0; i < 20_000; i++) {
            delegation.stake{value: delegation.MIN_DELEGATION()}();
            vm.deal(address(delegation), address(delegation).balance + 1 ether);
            vm.roll(block.number + 1);
        }
        vm.stopPrank();
        vm.startPrank(staker);
        uint256 expectedRewards = delegation.rewards();
        uint256 gas = gasleft();
        uint256 withdrawnRewards = delegation.withdrawAllRewards(12_000);
        assertLt(gas - gasleft(), 84_000_000, "gas used exceeds block limit");
        gas = gasleft();
        withdrawnRewards += delegation.withdrawAllRewards();
        assertLt(gas - gasleft(), 84_000_000, "gas used exceeds block limit");
        assertEq(expectedRewards, withdrawnRewards, "reward mismatch");
        vm.stopPrank();
    }

    function test_NoRewardsMissingWhenWithdrawingInSteps() public {
        uint256 depositAmount = 10_000_000 ether;
        addValidator(BaseDelegation(delegation), depositAmount, DepositMode.Bootstrapping);
        vm.deal(address(delegation), 1 ether);
        address staker = stakers[0];
        vm.deal(owner, depositAmount);
        vm.deal(staker, 2 * depositAmount);
        vm.startPrank(staker);
        delegation.stake{value: depositAmount}();
        vm.stopPrank();
        for (uint256 i = 0; i < 1_000; i++) {
            vm.startPrank(owner);
            delegation.stake{value: depositAmount / 1_000}();
            vm.stopPrank();
            vm.startPrank(staker);
            delegation.stake{value: depositAmount / 1_000}();
            vm.stopPrank();
            vm.deal(address(delegation), address(delegation).balance + 1 ether);
            vm.roll(block.number + 1);
        }
        vm.startPrank(staker);
        uint256 expectedRewards = delegation.rewards();
        Console.log("expected rewards: ", expectedRewards + 90 ether / 2);
        uint256 withdrawn = delegation.withdrawAllRewards(100);
        vm.deal(address(delegation), address(delegation).balance + 50 ether);
        withdrawn += delegation.withdrawAllRewards(500);
        vm.deal(address(delegation), address(delegation).balance + 50 ether);
        withdrawn += delegation.withdrawAllRewards();
        Console.log("withdrawn rewards:", withdrawn);
        vm.stopPrank();
        assertEq(withdrawn, expectedRewards + 90 ether / 2, "rewards skipped");
    }

    function test_OverflowLargeUnstake() public {
        uint256 stake = delegation.MIN_DELEGATION();
        addValidator(BaseDelegation(delegation), 10_000_000 ether, DepositMode.Bootstrapping);
        addValidator(BaseDelegation(delegations[0]), 10_000_000 ether, DepositMode.Bootstrapping);
        vm.startPrank(stakers[1]);
        vm.deal(stakers[1], stake);
        delegation.stake{value: stake}();
        vm.stopPrank();
        vm.startPrank(stakers[0]);
        vm.expectRevert();
        delegation.unstake(type(uint256).max - 10_000_000 ether - stake); // attacker will earn all the rewards after this
        return; // do not continue if unstaking failed
        delegation.unstake(10_000_000 ether + 1); // min value to make last unstake fail
        //delegation.unstake(10_000_000 ether + stake); // max value to make last unstake fail
        vm.roll(block.number + delegation.unbondingPeriod());
        vm.expectRevert();
        delegation.claim(); // fails since the first unstake() enqueued a huge withdrawal
        vm.stopPrank();
        vm.startPrank(stakers[2]);
        vm.deal(stakers[2], stake);
        delegation.stake{value: stake}();
        vm.stopPrank();
        vm.startPrank(stakers[2]);
        uint256 staker2BalanceBefore = stakers[2].balance;
        delegation.unstake(stake);
        vm.roll(block.number + delegation.unbondingPeriod());
        delegation.claim();
        assertEq(stakers[2].balance, staker2BalanceBefore + stake, "staker 2 claim failed");
        vm.stopPrank();
        vm.startPrank(owner);
        vm.deal(owner, 0);
        uint256 ownerBalanceBefore = owner.balance;
        delegation.unstake(10_000_000 ether);
        vm.roll(block.number + delegation.unbondingPeriod());
        delegation.claim();
        assertEq(owner.balance, ownerBalanceBefore + 10_000_000 ether, "owner claim failed");
        vm.stopPrank();
        vm.startPrank(stakers[1]);
        uint256 staker1BalanceBefore = stakers[1].balance;
        vm.expectRevert();
        delegation.unstake(stake);
        return; // do not continue if unstaking failed
        vm.roll(block.number + delegation.unbondingPeriod());
        delegation.claim();
        assertEq(stakers[1].balance, staker1BalanceBefore + stake, "staker 1 claim failed");
        vm.stopPrank();
    }

    function testFuzz_LargeUnstakeUndepositManyValidators(uint8 unstaked) public {
        uint256 max = delegation.MAX_VALIDATORS();
        vm.assume(unstaked < max && unstaked > 0);
        for (uint256 i = 0; i < max; i++)
            addValidator(BaseDelegation(delegation), 10_000_000 ether, DepositMode.Bootstrapping);
        assertEq(delegation.validators().length, max, "number of validators incorrect");
        vm.startPrank(owner);
        assertEq(delegation.getDelegatedAmount(), max * 10_000_000 ether, "delegated stake mitmatch");
        // if max == 255
        // unstake   1 * 10m -> claim requires  20,141,406 gas
        // unstake  27 * 10m -> claim requires  83,585,947 gas
        // unstake  28 * 10m -> claim requires  85,882,950 gas > block limit
        // unstake 100 * 10m -> claim requires 206,227,609 gas > block limit
        // unstake 125 * 10m -> claim requires 221,824,158 gas > block limit
        // unstake 150 * 10m -> claim requires 221,997,363 gas > block limit
        // unstake 200 * 10m -> claim requires 176,666,455 gas > block limit
        // unstake 247 * 10m -> claim requires  86,149,959 gas > block limit
        // unstake 248 * 10m -> claim requires  83,831,939 gas
        // unstake 254 * 10m -> claim requires  69,654,280 gas
        delegation.unstake(uint256(unstaked) * 10_000_000 ether);
        vm.roll(block.number + delegation.unbondingPeriod());
        uint256 gas = gasleft();
        delegation.claim();
        assertLt(gas - gasleft(), 84_000_000, "gas used exceeds block limit");
        vm.stopPrank();
    }

}