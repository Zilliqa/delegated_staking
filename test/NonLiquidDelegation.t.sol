// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import {NonLiquidDelegation} from "src/NonLiquidDelegation.sol";
import {NonLiquidDelegationV2} from "src/NonLiquidDelegationV2.sol";
import {WithdrawalQueue} from "src/BaseDelegation.sol";
import {Delegation} from "src/Delegation.sol";
import {Deposit, InitialStaker} from "src/Deposit.sol";
import {Console} from "src/Console.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Test, Vm} from "forge-std/Test.sol";
import "forge-std/console.sol";

contract NonLiquidDelegationTest is Test {
    address payable proxy;
    address owner;
    NonLiquidDelegationV2 delegation;
    address[4] staker = [
        0xd819fFcE7A58b1E835c25617Db7b46a00888B013,
        0x092E5E57955437876dA9Df998C96e2BE19341670,
        0xeA78aAE5Be606D2D152F00760662ac321aB8F017,
        0x6603A37980DF7ef6D44E994B3183A15D0322B7bF
    ];

    function setUp() public {
        vm.chainId(33469);
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        owner = vm.addr(deployerPrivateKey);
        //console.log("Signer is %s", owner);
        vm.deal(owner, 100_000 ether);
        vm.startPrank(owner);

        address oldImplementation = address(
            new NonLiquidDelegation()
        );

        bytes memory initializerCall = abi.encodeWithSelector(
            NonLiquidDelegation.initialize.selector,
            owner
        );

        proxy = payable(
            new ERC1967Proxy(oldImplementation, initializerCall)
        );
        /*
        console.log(
            "Proxy deployed: %s \r\n  Implementation deployed: %s",
            proxy,
            oldImplementation
        );
        //*/

        NonLiquidDelegation oldDelegation = NonLiquidDelegation(
            proxy
        );
        /*
        console.log("Deployed version: %s",
            oldDelegation.version()
        );

        console.log("Owner is %s",
            oldDelegation.owner()
        );
        //*/

        address payable newImplementation = payable(
            new NonLiquidDelegationV2()
        );

        /*
        console.log("New implementation deployed: %s",
            newImplementation
        );
        //*/

        bytes memory reinitializerCall = abi.encodeWithSelector(
            NonLiquidDelegationV2.reinitialize.selector
        );

        oldDelegation.upgradeToAndCall(
            newImplementation,
            reinitializerCall
        );

        delegation = NonLiquidDelegationV2(
            proxy
        );

        /*
        console.log("Upgraded to version: %s",
            delegation.version()
        );
        //*/
        /*
        Console.log("Old commission rate: %s.%s%s%%",
            delegation.getCommissionNumerator(),
            2
        );
        //*/
        uint256 commissionNumerator = 1_000;
        delegation.setCommissionNumerator(commissionNumerator);
        /*
        Console.log("New commission rate: %s.%s%s%%",
            delegation.getCommissionNumerator(),
            2
        );
        //*/

        InitialStaker[] memory initialStakers = new InitialStaker[](0);
        //vm.deployCodeTo("Deposit.sol", delegation.DEPOSIT_CONTRACT());
        vm.etch(
            delegation.DEPOSIT_CONTRACT(), //0x000000000000000000005a494C4445504F534954,
            address(new Deposit(10_000_000 ether, 256, 10, initialStakers)).code
        );
        vm.store(delegation.DEPOSIT_CONTRACT(), bytes32(uint256(11)), bytes32(uint256(block.number / 10)));
        vm.store(delegation.DEPOSIT_CONTRACT(), bytes32(uint256(12)), bytes32(uint256(10_000_000 ether)));
        vm.store(delegation.DEPOSIT_CONTRACT(), bytes32(uint256(13)), bytes32(uint256(256)));
        vm.store(delegation.DEPOSIT_CONTRACT(), bytes32(uint256(14)), bytes32(uint256(10)));
        /*
        console.log("Deposit.minimimStake() =", Deposit(delegation.DEPOSIT_CONTRACT()).minimumStake());
        console.log("Deposit.maximumStakers() =", Deposit(delegation.DEPOSIT_CONTRACT()).maximumStakers());
        console.log("Deposit.blocksPerEpoch() =", Deposit(delegation.DEPOSIT_CONTRACT()).blocksPerEpoch());
        //*/
        vm.stopPrank();
    }

    function deposit(
        uint256 depositAmount,
        bool initialDeposit
    ) internal {
        if (initialDeposit) {
            vm.deal(owner, owner.balance + depositAmount);
            vm.startPrank(owner);

            delegation.deposit{
                value: depositAmount
            }(
                bytes(hex"92fbe50544dce63cfdcc88301d7412f0edea024c91ae5d6a04c7cd3819edfc1b9d75d9121080af12e00f054d221f876c"),
                bytes(hex"002408011220d5ed74b09dcbe84d3b32a56c01ab721cf82809848b6604535212a219d35c412f"),
                bytes(hex"b14832a866a49ddf8a3104f8ee379d29c136f29aeb8fccec9d7fb17180b99e8ed29bee2ada5ce390cb704bc6fd7f5ce814f914498376c4b8bc14841a57ae22279769ec8614e2673ba7f36edc5a4bf5733aa9d70af626279ee2b2cde939b4bd8a")
            );
        } else {
            vm.deal(staker[0], staker[0].balance + depositAmount);
            vm.startPrank(staker[0]);

            vm.expectEmit(
                true,
                false,
                false,
                true,
                address(delegation)
            );
            emit Delegation.Staked(
                staker[0],
                depositAmount,
                ""
            );

            delegation.stake{
                value: depositAmount
            }();

            vm.startPrank(owner);

            delegation.deposit2(
                bytes(hex"92fbe50544dce63cfdcc88301d7412f0edea024c91ae5d6a04c7cd3819edfc1b9d75d9121080af12e00f054d221f876c"),
                bytes(hex"002408011220d5ed74b09dcbe84d3b32a56c01ab721cf82809848b6604535212a219d35c412f"),
                bytes(hex"b14832a866a49ddf8a3104f8ee379d29c136f29aeb8fccec9d7fb17180b99e8ed29bee2ada5ce390cb704bc6fd7f5ce814f914498376c4b8bc14841a57ae22279769ec8614e2673ba7f36edc5a4bf5733aa9d70af626279ee2b2cde939b4bd8a")
            );
        }
        // wait 2 epochs for the change to the deposit to take affect
        vm.roll(block.number + Deposit(delegation.DEPOSIT_CONTRACT()).blocksPerEpoch() * 2);
    }

    function findStaker(address a) internal view returns(uint256) {
        for (uint256 i = 0; i < staker.length; i++)
            if (staker[i] == a)
                return i;
        revert("staker not found");
    }  

    function snapshot(string memory s, uint256 i, uint256 x) internal view {
        console.log("-----------------------------------------------");
        console.log(s, i, x);
        uint256[] memory shares = new uint256[](staker.length);
        NonLiquidDelegationV2.Staking[] memory stakings = delegation.getStakingHistory();
        for (i = 0; i < stakings.length; i++)
        //i = stakings.length - 1;
        {
            uint256 stakerIndex = findStaker(stakings[i].staker);
            shares[stakerIndex] = stakings[i].amount;
            s = string.concat("index: ", Strings.toString(i));
            s = string.concat(s, "\tstaker ");
            assertEq(stakings[i].staker, staker[stakerIndex], "found staker mismatch");
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
        (uint64[] memory stakingIndices, uint64 firstStakingIndex, uint256 allWithdrawnRewards, uint64 lastWithdrawnRewardIndex) = delegation.getStakingData();
        Console.log("stakingIndices: %s", stakingIndices);
        console.log("firstStakingIndex: %s   lastWithdrawnRewardIndex: %s   allWithdrawnRewards: %s", firstStakingIndex, lastWithdrawnRewardIndex, allWithdrawnRewards);
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
            staker[0] = owner;
        deposit(depositAmount, initialDeposit);

        for (uint256 i = 0; i < staker.length; i++) {
            vm.deal(staker[i], 10 * depositAmount);
            console.log("staker %s: %s", i+1, staker[i]);
        } 

        delegation = NonLiquidDelegationV2(proxy);

        // rewards accrued so far
        vm.deal(address(delegation), rewardsBeforeStaking - rewardsAccruedAfterEach);

        for (uint256 i = 0; i < stakerIndicesBeforeWithdrawals.length; i++) {
            vm.deal(address(delegation), address(delegation).balance + rewardsAccruedAfterEach);
            int256 x = relativeAmountsBeforeWithdrawals[i] * int256(depositAmount) / 10;
            vm.startPrank(staker[stakerIndicesBeforeWithdrawals[i]-1]);
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
            vm.startPrank(staker[i-1]);
            if (steps == 123_456_789)
                snapshot("staker %s withdrawing all, remaining rewards:", i, 0);
            else
                snapshot("staker %s withdrawing 1+%s times", i, steps);
            Console.log("rewards accrued until last staking: %s.%s%s", delegation.getTotalRewards());
            Console.log("delegation contract balance: %s.%s%s", address(delegation).balance);
            //Console.log("staker balance: %s.%s%s", staker[i-1].balance);
            Console.log("staker rewards: %s.%s%s", delegation.rewards());
            if (steps == 123_456_789)
                Console.log("staker withdrew: %s.%s%s", delegation.withdrawAllRewards());
            else
                Console.log("staker withdrew: %s.%s%s", delegation.withdrawRewards(delegation.rewards(steps), steps));
            Console.log("rewards accrued until last staking: %s.%s%s", delegation.getTotalRewards());
            Console.log("delegation contract balance: %s.%s%s", address(delegation).balance);
            //Console.log("staker balance: %s.%s%s", staker[i-1].balance);
            vm.stopPrank();
        }

        for (uint256 i = 0; i < stakerIndicesAfterWithdrawals.length; i++) {
            vm.deal(address(delegation), address(delegation).balance + rewardsAccruedAfterEach);
            int256 x = relativeAmountsAfterWithdrawals[i] * int256(depositAmount) / 10;
            vm.startPrank(staker[stakerIndicesAfterWithdrawals[i]-1]);
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

        for (uint256 i = 1; i <= staker.length; i++) {
            vm.startPrank(staker[i-1]);
            if (steps == 123_456_789)
                snapshot("staker %s withdrawing all, remaining rewards:", i, 0);
            else
                snapshot("staker %s withdrawing 1+%s times", i, steps);
            Console.log("rewards accrued until last staking: %s.%s%s", delegation.getTotalRewards());
            Console.log("delegation contract balance: %s.%s%s", address(delegation).balance);
            //Console.log("staker balance: %s.%s%s", staker[i-1].balance);
            Console.log("staker rewards: %s.%s%s", delegation.rewards());
            if (steps == 123_456_789)
                Console.log("staker withdrew: %s.%s%s", delegation.withdrawAllRewards());
            else
                //TODO: add a test that withdraws a fixed amount < delegation.rewards(step)
                Console.log("staker withdrew: %s.%s%s", delegation.withdrawRewards(delegation.rewards(steps), steps));
            Console.log("rewards accrued until last staking: %s.%s%s", delegation.getTotalRewards());
            Console.log("delegation contract balance: %s.%s%s", address(delegation).balance);
            //Console.log("staker balance: %s.%s%s", staker[i-1].balance);
            vm.stopPrank();
        }

        // if we try to withdraw again immediately (in the same block),
        // the amount withdrawn must equal zero
        //*
        for (uint256 i = 1; i <= staker.length; i++) {
            vm.startPrank(staker[i-1]);
            if (steps == 123_456_789)
                snapshot("staker %s withdrawing all, remaining rewards:", i, 0);
            else
                snapshot("staker %s withdrawing 1+%s times", i, steps);
            Console.log("rewards accrued until last staking: %s.%s%s", delegation.getTotalRewards());
            Console.log("delegation contract balance: %s.%s%s", address(delegation).balance);
            //Console.log("staker balance: %s.%s%s", staker[i-1].balance);
            Console.log("staker rewards: %s.%s%s", delegation.rewards());
            if (steps == 123_456_789)
                Console.log("staker withdrew: %s.%s%s", delegation.withdrawAllRewards());
            else
                //TODO: add a test that withdraws a fixed amount < delegation.rewards(step)
                Console.log("staker withdrew: %s.%s%s", delegation.withdrawRewards(delegation.rewards(steps), steps));
            Console.log("rewards accrued until last staking: %s.%s%s", delegation.getTotalRewards());
            Console.log("delegation contract balance: %s.%s%s", address(delegation).balance);
            //Console.log("staker balance: %s.%s%s", staker[i-1].balance);
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

        deposit(10_000_000 ether, true);

        // wait 2 epochs for the change to the deposit to take affect
        vm.roll(block.number + Deposit(delegation.DEPOSIT_CONTRACT()).blocksPerEpoch() * 2);

        for (i = 0; i < 4; i++) {
            vm.deal(staker[i], 100_000 ether);
            console.log("staker %s: %s", i+1, staker[i]);
        }

        delegation = NonLiquidDelegationV2(proxy);

        // rewards accrued so far
        vm.deal(address(delegation), 50_000 ether);
        x = 50;
        for (uint256 j = 0; j < steps / 8; j++) {
            for (i = 1; i <= 4; i++) {
                vm.startPrank(staker[i-1]);
                vm.recordLogs();
                vm.expectEmit(
                    true,
                    false,
                    false,
                    false,
                    address(delegation)
                );
                emit Delegation.Staked(
                    staker[i-1],
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
                vm.startPrank(staker[i-1]);
                vm.recordLogs();
                vm.expectEmit(
                    true,
                    false,
                    false,
                    false,
                    address(delegation)
                );
                emit Delegation.Unstaked(
                    staker[i-1],
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
        vm.startPrank(staker[i-1]);
        //snapshot("staker %s withdrawing 1+%s times", i, steps);
        //Console.log("staker balance: %s.%s%s", staker[i-1].balance);
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
        //Console.log("staker balance: %s.%s%s", staker[i-1].balance);
        vm.stopPrank();

        vm.roll(block.number + WithdrawalQueue.unbondingPeriod());
        //TODO: remove the next line once https://github.com/Zilliqa/zq2/issues/1761 is fixed
        vm.warp(block.timestamp + WithdrawalQueue.unbondingPeriod());


        i = 1;
        vm.startPrank(staker[i-1]);
        vm.recordLogs();
        vm.expectEmit(
            true,
            false,
            false,
            false,
            address(delegation)
        );
        emit Delegation.Claimed(
            staker[i-1],
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
        staker[0] = owner;
        deposit(10_000_000 ether, true);

        // wait 2 epochs for the change to the deposit to take affect
        vm.roll(block.number + Deposit(delegation.DEPOSIT_CONTRACT()).blocksPerEpoch() * 2);

        for (i = 0; i < 4; i++) {
            vm.deal(staker[i], 100_000 ether);
        }

        delegation = NonLiquidDelegationV2(proxy);

        // rewards accrued so far
        vm.deal(address(delegation), 50_000 ether);
        x = 50;
        i = 2;
        vm.startPrank(staker[i-1]);
        vm.recordLogs();
        vm.expectEmit(
            true,
            false,
            false,
            false,
            address(delegation)
        );
        emit Delegation.Staked(
            staker[i-1],
            x * 1 ether,
            ""
        );
        delegation.stake{value: x * 1 ether}();

        // wait 2 epochs for the change to the deposit to take affect
        vm.roll(block.number + Deposit(delegation.DEPOSIT_CONTRACT()).blocksPerEpoch() * 2);
        vm.stopPrank();

        vm.deal(address(delegation), address(delegation).balance + 10_000 ether);
        vm.startPrank(staker[i-1]);
        snapshot("staker %s withdrawing all, remaining rewards:", i, 0);
        console.log("-----------------------------------------------");

        Console.log("contract balance: %s.%s%s", address(delegation).balance);
        Console.log("staker balance: %s.%s%s", staker[i-1].balance);
        uint256 rewards = delegation.rewards();
        Console.log("staker rewards: %s.%s%s", rewards);

        (
        uint64[] memory stakingIndices,
        uint64 firstStakingIndex,
        uint256 allWithdrawnRewards,
        uint64 lastWithdrawnRewardIndex
        ) = delegation.getStakingData();
        Console.log("stakingIndices = [ %s]", stakingIndices);
        console.log("firstStakingIndex = %s   allWithdrawnRewards = %s   lastWithdrawnRewardIndex = %s", uint(firstStakingIndex), allWithdrawnRewards, uint(lastWithdrawnRewardIndex));

        vm.recordLogs();
        vm.expectEmit(
            true,
            true,
            true,
            true,
            address(delegation)
        );
        emit NonLiquidDelegationV2.RewardPaid(
            staker[i-1],
            rewards
        );
        rewards = delegation.withdrawAllRewards();

        (
        stakingIndices,
        firstStakingIndex,
        allWithdrawnRewards,
        lastWithdrawnRewardIndex
        ) = delegation.getStakingData();
        Console.log("stakingIndices = [ %s]", stakingIndices);
        console.log("firstStakingIndex = %s   allWithdrawnRewards = %s   lastWithdrawnRewardIndex = %s", uint(firstStakingIndex), allWithdrawnRewards, uint(lastWithdrawnRewardIndex));

        Console.log("contract balance: %s.%s%s", address(delegation).balance);
        Console.log("staker balance: %s.%s%s", staker[i-1].balance);
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