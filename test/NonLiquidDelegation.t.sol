// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import {NonLiquidDelegation} from "src/NonLiquidDelegation.sol";
import {Deposit} from "src/Deposit.sol";
import {Console} from "src/Console.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Test, Vm} from "forge-std/Test.sol";
import "forge-std/console.sol";

contract NonLiquidDelegationTest is Test {
    address payable proxy;
    address owner;
    NonLiquidDelegation delegation;
    address[4] staker = [
        0xd819fFcE7A58b1E835c25617Db7b46a00888B013,
        0x092E5E57955437876dA9Df998C96e2BE19341670,
        0xeA78aAE5Be606D2D152F00760662ac321aB8F017,
        0x6603A37980DF7ef6D44E994B3183A15D0322B7bF
    ];

    function setUp() public {
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
        //NonLiquidDelegation oldDelegation = NonLiquidDelegation(
        delegation = NonLiquidDelegation(
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
        /*
        address payable newImplementation = payable(
            new NonLiquidDelegationV2()
        );
        //*/
        /*
        console.log("New implementation deployed: %s",
            newImplementation
        );
        //*/
        /*
        bytes memory reinitializerCall = abi.encodeWithSelector(
            NonLiquidDelegationV2.reinitialize.selector
        );

        oldDelegation.upgradeToAndCall(
            newImplementation,
            reinitializerCall
        );

        NonLiquidDelegationV2 delegation = NonLiquidDelegationV2(
                proxy
            );
        //*/
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

        //vm.deployCodeTo("Deposit.sol", delegation.DEPOSIT_CONTRACT());
        vm.etch(
            delegation.DEPOSIT_CONTRACT(), //0x000000000000000000005a494C4445504F534954,
            address(new Deposit(10_000_000 ether, 256)).code
        );
        vm.store(delegation.DEPOSIT_CONTRACT(), bytes32(uint256(3)), bytes32(uint256(10_000_000 ether)));
        vm.store(delegation.DEPOSIT_CONTRACT(), bytes32(uint256(4)), bytes32(uint256(256)));
        /*
        console.log("Deposit._minimimStake() =", Deposit(delegation.DEPOSIT_CONTRACT())._minimumStake());
        console.log("Deposit._maximumStakers() =", Deposit(delegation.DEPOSIT_CONTRACT())._maximumStakers());
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

            /*TODO: uncomment the following section once events are implemented
            vm.expectEmit(
                true,
                false,
                false,
                true,
                address(delegation)
            );
            emit NonLiquidDelegation.Staked(
                staker[0],
                depositAmount,
                depositAmount
            );*/

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
    }

    function findStaker(address a) internal returns(uint256) {
        for (uint256 i = 0; i < staker.length; i++)
            if (staker[i] == a)
                return i;
        return 0;
    }  

    function snapshot(string memory s, uint256 i, uint256 x) internal {
        console.log("-----------------------------------------------");
        console.log(s, i, x);
        //assertEq(msg.sender, staker[i-1], "prank mismatch");
        uint256[] memory shares = new uint256[](staker.length);
        NonLiquidDelegation.Staking[] memory stakings = delegation.getStakingHistory();
        for (i = 0; i < stakings.length; i++)
        //i = stakings.length - 1;
        {
            uint256 stakerIndex = findStaker(stakings[i].staker);
            shares[stakerIndex] = stakings[i].amount;
            s = string.concat("index: ", Strings.toString(i));
            s = string.concat(s, "   staker ");
            assertEq(stakings[i].staker, staker[stakerIndex], "found staker mismatch");
            s = string.concat(s, Strings.toString(stakerIndex + 1));
            s = string.concat(s, ": ");
            s = string.concat(s, Strings.toHexString(stakings[i].staker));
            s = string.concat(s, "   amount: ");
            s = string.concat(s, Strings.toString(stakings[i].amount / 1 ether));
            s = string.concat(s, "   total: ");
            s = string.concat(s, Strings.toString(stakings[i].total / 1 ether));
            s = string.concat(s, "   rewards: ");
            s = string.concat(s, Strings.toString(stakings[i].rewards / 1 ether));
            s = string.concat(s, "   shares: ");
            for (uint256 j = 0; j < shares.length; j++)
                s = string.concat(s, string.concat(Console.toString(10**6 * shares[j] / stakings[i].total, 4), "%  "));
            console.log(s);
        } 
        (uint256[] memory stakingIndices, uint256 firstStakingIndex, uint256 allWithdrawnRewards, uint256 lastWithdrawnRewardIndex) = delegation.getStakingData();
        Console.log("stakingIndices: %s", stakingIndices);
        console.log("firstStakingIndex: %s   lastWithdrawnRewardIndex: %s   allWithdrawnRewards: %s", firstStakingIndex, lastWithdrawnRewardIndex, allWithdrawnRewards);
    } 

    function test_withdrawAllRewards() public {
        uint256 i;
        uint256 x;

        //TODO: also test staking and unstaking before depositing
        deposit(10_000_000 ether, true);

        for (i = 0; i < 4; i++) { 
            vm.deal(staker[i], 100 ether);
            console.log("staker %s: %s", i+1, staker[i]);
        } 

        delegation = NonLiquidDelegation(proxy);

        // rewards accrued since the deposit
        vm.deal(address(delegation), 50_000 ether);
        i = 1; x = 50;
        vm.startPrank(staker[i-1]);
        delegation.stake{value: x * 1 ether}();
        //snapshot("staker %s staked %s", i, x);

        vm.deal(address(delegation), address(delegation).balance + 10_000 ether);
        i = 2; x = 50;
        vm.stopPrank();
        vm.startPrank(staker[i-1]);
        delegation.stake{value: x * 1 ether}();
        //snapshot("staker %s staked %s", i, x);

        vm.deal(address(delegation), address(delegation).balance + 10_000 ether);
        i = 3; x = 25;
        vm.stopPrank();
        vm.startPrank(staker[i-1]);
        delegation.stake{value: x * 1 ether}();
        //snapshot("staker %s staked %s", i, x);

        vm.deal(address(delegation), address(delegation).balance + 10_000 ether);
        i = 1; x = 35;
        vm.stopPrank();
        vm.startPrank(staker[i-1]);
        delegation.stake{value: x * 1 ether}();
        //snapshot("staker %s staked %s", i, x);

        vm.deal(address(delegation), address(delegation).balance + 10_000 ether);
        i = 2; x = 35;
        vm.stopPrank();
        vm.startPrank(staker[i-1]);
        delegation.unstake(x * 1 ether);
        //snapshot("staker %s unstaked %s", i, x);

        //*
        i = 1;
        vm.stopPrank();
        vm.startPrank(staker[i-1]);
        snapshot("staker %s withdrawing all, remaining rewards:", i, 0);
        //Console.log("staker balance: %s.%s%s", staker[i-1].balance);
        Console.log("staker rewards: %s.%s%s", delegation.rewards());
        Console.log("staker withdrew: %s.%s%s", delegation.withdrawAllRewards());
        //Console.log("staker balance: %s.%s%s", staker[i-1].balance);

        i = 2;
        vm.stopPrank();
        vm.startPrank(staker[i-1]);
        snapshot("staker %s withdrawing all, remaining rewards:", i, 0);
        //Console.log("staker balance: %s.%s%s", staker[i-1].balance);
        Console.log("staker rewards: %s.%s%s", delegation.rewards());
        Console.log("staker withdrew: %s.%s%s", delegation.withdrawAllRewards());
        //Console.log("staker balance: %s.%s%s", staker[i-1].balance);
        //*/

        vm.deal(address(delegation), address(delegation).balance + 10_000 ether);
        i = 4; x = 40;
        vm.stopPrank();
        vm.startPrank(staker[i-1]);
        delegation.stake{value: x * 1 ether}();
        //snapshot("staker %s staked %s", i, x);

        //further rewards accrued since the last staking
        vm.deal(address(delegation), address(delegation).balance + 10_000 ether);

        //*
        i = 1;
        vm.stopPrank();
        vm.startPrank(staker[i-1]);
        snapshot("staker %s withdrawing all, remaining rewards:", i, 0);
        //Console.log("staker balance: %s.%s%s", staker[i-1].balance);
        Console.log("staker rewards: %s.%s%s", delegation.rewards());
        Console.log("staker withdrew: %s.%s%s", delegation.withdrawAllRewards());
        //Console.log("staker balance: %s.%s%s", staker[i-1].balance);

        i = 2;
        vm.stopPrank();
        vm.startPrank(staker[i-1]);
        snapshot("staker %s withdrawing all, remaining rewards:", i, 0);
        //Console.log("staker balance: %s.%s%s", staker[i-1].balance);
        Console.log("staker rewards: %s.%s%s", delegation.rewards());
        Console.log("staker withdrew: %s.%s%s", delegation.withdrawAllRewards());
        //Console.log("staker balance: %s.%s%s", staker[i-1].balance);

        i = 3;
        vm.stopPrank();
        vm.startPrank(staker[i-1]);
        snapshot("staker %s withdrawing all, remaining rewards:", i, 0);
        //Console.log("staker balance: %s.%s%s", staker[i-1].balance);
        Console.log("staker rewards: %s.%s%s", delegation.rewards());
        Console.log("staker withdrew: %s.%s%s", delegation.withdrawAllRewards());
        //Console.log("staker balance: %s.%s%s", staker[i-1].balance);

        i = 4;
        vm.stopPrank();
        vm.startPrank(staker[i-1]);
        snapshot("staker %s withdrawing all, remaining rewards:", i, 0);
        //Console.log("staker balance: %s.%s%s", staker[i-1].balance);
        Console.log("staker rewards: %s.%s%s", delegation.rewards());
        Console.log("staker withdrew: %s.%s%s", delegation.withdrawAllRewards());
        //Console.log("staker balance: %s.%s%s", staker[i-1].balance);
        //*/
        vm.stopPrank();
    } 

    function test_withdrawSomeRewards() public {
        uint256 i;
        uint256 x;
        uint256 steps = 8;

        //TODO: also test staking and unstaking before depositing
        deposit(10_000_000 ether, true);

        for (i = 0; i < 4; i++) { 
            vm.deal(staker[i], 100 ether);
            console.log("staker %s: %s", i+1, staker[i]);
        } 

        delegation = NonLiquidDelegation(proxy);

        // rewards accrued since the deposit
        vm.deal(address(delegation), 50_000 ether);
        i = 1; x = 50;
        vm.startPrank(staker[i-1]);
        delegation.stake{value: x * 1 ether}();
        //snapshot("staker %s staked %s", i, x);

        vm.deal(address(delegation), address(delegation).balance + 10_000 ether);
        i = 2; x = 50;
        vm.stopPrank();
        vm.startPrank(staker[i-1]);
        delegation.stake{value: x * 1 ether}();
        //snapshot("staker %s staked %s", i, x);

        vm.deal(address(delegation), address(delegation).balance + 10_000 ether);
        i = 3; x = 25;
        vm.stopPrank();
        vm.startPrank(staker[i-1]);
        delegation.stake{value: x * 1 ether}();
        //snapshot("staker %s staked %s", i, x);

        vm.deal(address(delegation), address(delegation).balance + 10_000 ether);
        i = 1; x = 35;
        vm.stopPrank();
        vm.startPrank(staker[i-1]);
        delegation.stake{value: x * 1 ether}();
        //snapshot("staker %s staked %s", i, x);

        vm.deal(address(delegation), address(delegation).balance + 10_000 ether);
        i = 2; x = 35;
        vm.stopPrank();
        vm.startPrank(staker[i-1]);
        delegation.unstake(x * 1 ether);
        //snapshot("staker %s unstaked %s", i, x);

        //*
        i = 1;
        vm.stopPrank();
        vm.startPrank(staker[i-1]);
        snapshot("staker %s withdrawing 1+%s times", i, steps);
        //Console.log("staker balance: %s.%s%s", staker[i-1].balance);
        Console.log("staker rewards: %s.%s%s", delegation.rewards());
        Console.log("staker withdrew: %s.%s%s", delegation.withdrawRewards(0, steps));
        //Console.log("staker balance: %s.%s%s", staker[i-1].balance);

        i = 2;
        vm.stopPrank();
        vm.startPrank(staker[i-1]);
        snapshot("staker %s withdrawing 1+%s times", i, steps);
        //Console.log("staker balance: %s.%s%s", staker[i-1].balance);
        Console.log("staker rewards: %s.%s%s", delegation.rewards());
        Console.log("staker withdrew: %s.%s%s", delegation.withdrawRewards(0, steps));
        //Console.log("staker balance: %s.%s%s", staker[i-1].balance);
        //*/

        vm.deal(address(delegation), address(delegation).balance + 10_000 ether);
        i = 4; x = 40;
        vm.stopPrank();
        vm.startPrank(staker[i-1]);
        delegation.stake{value: x * 1 ether}();
        //snapshot("staker %s staked %s", i, x);

        //further rewards accrued since the last staking
        vm.deal(address(delegation), address(delegation).balance + 10_000 ether);

        //*
        i = 1;
        vm.stopPrank();
        vm.startPrank(staker[i-1]);
        snapshot("staker %s withdrawing 1+%s times", i, steps);
        //Console.log("staker balance: %s.%s%s", staker[i-1].balance);
        Console.log("staker rewards: %s.%s%s", delegation.rewards());
        Console.log("staker withdrew: %s.%s%s", delegation.withdrawRewards(0, steps));
        //Console.log("staker balance: %s.%s%s", staker[i-1].balance);

        i = 2;
        vm.stopPrank();
        vm.startPrank(staker[i-1]);
        snapshot("staker %s withdrawing 1+%s times", i, steps);
        //Console.log("staker balance: %s.%s%s", staker[i-1].balance);
        Console.log("staker rewards: %s.%s%s", delegation.rewards());
        Console.log("staker withdrew: %s.%s%s", delegation.withdrawRewards(0, steps));
        //Console.log("staker balance: %s.%s%s", staker[i-1].balance);

        i = 3;
        vm.stopPrank();
        vm.startPrank(staker[i-1]);
        snapshot("staker %s withdrawing 1+%s times", i, steps);
        //Console.log("staker balance: %s.%s%s", staker[i-1].balance);
        Console.log("staker rewards: %s.%s%s", delegation.rewards());
        Console.log("staker withdrew: %s.%s%s", delegation.withdrawRewards(0, steps));
        //Console.log("staker balance: %s.%s%s", staker[i-1].balance);

        i = 4;
        vm.stopPrank();
        vm.startPrank(staker[i-1]);
        snapshot("staker %s withdrawing 1+%s times", i, steps);
        //Console.log("staker balance: %s.%s%s", staker[i-1].balance);
        Console.log("staker rewards: %s.%s%s", delegation.rewards());
        Console.log("staker withdrew: %s.%s%s", delegation.withdrawRewards(0, steps));
        //Console.log("staker balance: %s.%s%s", staker[i-1].balance);
        //*/
        vm.stopPrank();
    }

//index user/indices 1 (0,3) 2 (1,4) 3 (2)   4 (5)   total   1%      2%      3%      4%      rewards
//==================================================================================================
//    0 stake        50                              50      100                             0
//    1 stake        50      50                      100     50      50                      10_000
//    2 stake        50      50      25              125     40      40      20              10_000
//    3 stake        50+35   50      25              160     53.125  31.25   15.625          10_000
//    4 unstake      85      50-35   25              125     68      12      20              10_000
//      withdraw all 24312
//      withdraw all         12125
//    5 stake        85      15      25      40      165     51.5152 9.0909  15.1515 24.2424 10_000
//      withdraw all 6800    1200    5562    0
//                   -------------------------------
//      sum          31112   13325   5562    0       49999
} 