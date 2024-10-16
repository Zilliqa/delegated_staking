// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import {Delegation} from  "src/Delegation.sol";
import {DelegationV2} from  "src/DelegationV2.sol";
import {NonRebasingLST} from "src/NonRebasingLST.sol";
import {Deposit} from  "src/Deposit.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Test, Vm} from "forge-std/Test.sol";
import "forge-std/console.sol";

library Console {
    function log(string memory format, uint256 amount) external {
        string memory zeros = "";
        uint256 decimals = amount % 10**18;
        while (decimals > 0 && decimals < 10**17) {
            //console.log("%s %s", zeros, decimals);
            zeros = string.concat(zeros, "0");
            decimals *= 10;
        }
        console.log(
            format,
            amount / 10**18,
            zeros,
            amount % 10**18
        );
    } 
} 

contract DelegationTest is Test {
    address payable proxy;
    address owner;
    address staker = 0xd819fFcE7A58b1E835c25617Db7b46a00888B013;

    function setUp() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        owner = vm.addr(deployerPrivateKey);
        //console.log("Signer is %s", owner);
        vm.deal(owner, 100_000 ether);
        vm.startPrank(owner);

        address oldImplementation = address(
            new Delegation()
        );

        bytes memory initializerCall = abi.encodeWithSelector(
            Delegation.initialize.selector,
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
        Delegation oldDelegation = Delegation(
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
            new DelegationV2()
        );
        /*
        console.log("New implementation deployed: %s",
            newImplementation
        );
        //*/
        bytes memory reinitializerCall = abi.encodeWithSelector(
            DelegationV2.reinitialize.selector
        );

        oldDelegation.upgradeToAndCall(
            newImplementation,
            reinitializerCall
        );

        DelegationV2 delegation = DelegationV2(
                proxy
            );
        /*
        console.log("Upgraded to version: %s",
            delegation.version()
        );
        //*/
        NonRebasingLST lst = NonRebasingLST(delegation.getLST());
        /*
        console.log("LST address: %s",
            address(lst)
        );

        console.log("Old commission rate: %s.%s%%",
            uint256(delegation.getCommissionNumerator()) * 100 / uint256(delegation.DENOMINATOR()),
            //TODO: check if the decimals are printed correctly e.g. 12.01% vs 12.1%
            uint256(delegation.getCommissionNumerator()) % (uint256(delegation.DENOMINATOR()) / 100)
        );
        //*/
        uint256 commissionNumerator = 1_000;
        delegation.setCommissionNumerator(commissionNumerator);
        /*
        console.log("New commission rate: %s.%s%%",
            uint256(delegation.getCommissionNumerator()) * 100 / uint256(delegation.DENOMINATOR()),
            //TODO: check if the decimals are printed correctly e.g. 12.01% vs 12.1%
            uint256(delegation.getCommissionNumerator()) % (uint256(delegation.DENOMINATOR()) / 100)
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
    }

    function run(
        uint256 depositAmount,
        uint256 rewardsBefore,
        uint256 delegatedAmount,
        uint256 rewardsAfter,
        uint256 blocksUntil,
        bool initialDeposit
    ) public {
        DelegationV2 delegation = DelegationV2(proxy);
        NonRebasingLST lst = NonRebasingLST(delegation.getLST());

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
            vm.deal(staker, staker.balance + depositAmount);
            vm.startPrank(staker);

            vm.expectEmit(
                true,
                false,
                false,
                true,
                address(delegation)
            );
            emit DelegationV2.Staked(
                staker,
                depositAmount,
                depositAmount
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

        vm.deal(address(delegation), rewardsBefore);
        vm.deal(staker, 100_000 ether);
        vm.startPrank(staker);

        Console.log("Stake deposited before staking: %s.%s%s ZIL",
            delegation.getStake()
        );

        Console.log("Rewards before staking: %s.%s%s ZIL",
            delegation.getRewards()
        );

        Console.log("Staker balance before staking: %s.%s%s ZIL",
            staker.balance
        );

        Console.log("Staker balance before staking: %s.%s%s LST",
            lst.balanceOf(staker)
        );

        Console.log("Total supply before staking: %s.%s%s LST", 
            lst.totalSupply()
        );

        vm.recordLogs();

        vm.expectEmit(
            true,
            false,
            false,
            false,
            address(delegation)
        );
        emit DelegationV2.Staked(
            staker,
            delegatedAmount,
            lst.totalSupply() * delegatedAmount / (delegation.getStake() + delegation.getRewards())
        );

        uint256 ownerZILBefore = delegation.owner().balance;

        delegation.stake{
            value: delegatedAmount
        }();

        uint256 ownerZILAfter = delegation.owner().balance;

        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 loggedAmount;
        uint256 loggedShares;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("Staked(address,uint256,uint256)")) { 
                (loggedAmount, loggedShares) = abi.decode(entries[i].data, (uint256, uint256));
                //console.log(loggedAmount, loggedShares);
            } 
        }
        //console.log(delegatedAmount, (lst.totalSupply() - lst.balanceOf(staker)) * delegatedAmount / (delegation.getStake() + delegation.getTaxedRewards()));
        //console.log(delegatedAmount, lst.balanceOf(staker));

        Console.log("Owner commission after staking: %s.%s%s ZIL", 
            ownerZILAfter - ownerZILBefore
        );

        Console.log("Stake deposited after staking: %s.%s%s ZIL",
            delegation.getStake()
        );

        Console.log("Rewards after staking: %s.%s%s ZIL",
            delegation.getRewards()
        );

        Console.log("Staker balance after staking: %s.%s%s ZIL",
            staker.balance
        );

        Console.log("Staker balance after staking: %s.%s%s LST",
            lst.balanceOf(staker)
        );

        Console.log("Total supply after staking: %s.%s%s LST", 
            lst.totalSupply()
        );

        vm.deal(address(delegation), address(delegation).balance + rewardsAfter);

        Console.log("LST price: %s.%s%s",
            10**18 * (delegation.getStake() + delegation.getRewards()) / lst.totalSupply()
        );

        Console.log("LST value: %s.%s%s",
            lst.balanceOf(staker) * (delegation.getStake() + delegation.getRewards()) / lst.totalSupply()
        );

        vm.recordLogs();

        vm.expectEmit(
            true,
            false,
            false,
            false,
            address(delegation)
        );
        emit DelegationV2.Unstaked(
            staker,
            (delegation.getStake() + delegation.getRewards()) * lst.balanceOf(staker) / lst.totalSupply(),
            lst.balanceOf(staker)
        );

        uint256 stakerLSTBefore = lst.balanceOf(staker);
        ownerZILBefore = delegation.owner().balance;

        delegation.unstake(
            initialDeposit ? lst.balanceOf(staker) : lst.balanceOf(staker) - depositAmount
        );

        uint256 stakerLSTAfter = lst.balanceOf(staker);
        ownerZILAfter = delegation.owner().balance;

        entries = vm.getRecordedLogs();
        
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("Unstaked(address,uint256,uint256)")) {
                (loggedAmount, loggedShares) = abi.decode(entries[i].data, (uint256, uint256));
                //console.log(loggedAmount, loggedShares);
            } 
        }
        //TODO: why is loggedAmount equal to the value below without adding back lst.totalSupply() + stakerLSTBefore although unstake() burns stakerLSTBefore before computing the amount?
        //console.log((delegation.getStake() + delegation.getTaxedRewards()) * stakerLSTBefore / lst.totalSupply(), stakerLSTBefore - stakerLSTAfter);
        
        Console.log("Owner commission after unstaking: %s.%s%s ZIL", 
            ownerZILAfter - ownerZILBefore
        );

        Console.log("Stake deposited after unstaking: %s.%s%s ZIL",
            delegation.getStake()
        );

        Console.log("Rewards after unstaking: %s.%s%s ZIL",
            delegation.getRewards()
        );

        Console.log("Staker balance after unstaking: %s.%s%s ZIL",
            staker.balance
        );

        Console.log("Staker balance after unstaking: %s.%s%s LST",
            lst.balanceOf(staker)
        );

        Console.log("Total supply after unstaking: %s.%s%s LST", 
            lst.totalSupply()
        );

        vm.roll(block.number + blocksUntil);

        vm.recordLogs();

        uint256 unstakedAmount = loggedAmount; // the amount we logged on unstaking
        vm.expectEmit(
            true,
            false,
            false,
            false,
            address(delegation)
        );
        emit DelegationV2.Claimed(
            staker,
            unstakedAmount
        );

        uint256 stakerZILBefore = staker.balance;
        ownerZILBefore = delegation.owner().balance;

        delegation.claim();

        uint256 stakerZILAfter = staker.balance;
        ownerZILAfter = delegation.owner().balance;

        entries = vm.getRecordedLogs();

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("Claimed(address,uint256)")) {
                loggedAmount = abi.decode(entries[i].data, (uint256));
                //console.log(loggedAmount);
            } 
        } 
        //console.log(stakerZILAfter - stakerZILBefore);
        //console.log(unstakedAmount);

        Console.log("Owner commission after claiming: %s.%s%s ZIL", 
            ownerZILAfter - ownerZILBefore
        );

        Console.log("Stake deposited after claiming: %s.%s%s ZIL",
            delegation.getStake()
        );

        Console.log("Rewards after claiming: %s.%s%s ZIL",
            delegation.getRewards()
        );

        Console.log("Staker balance after claiming: %s.%s%s ZIL",
            staker.balance
        );

        Console.log("Staker balance after claiming: %s.%s%s LST",
            lst.balanceOf(staker)
        );

        Console.log("Total supply after claiming: %s.%s%s LST", 
            lst.totalSupply()
        );

    }

    function test_Real() public {
        //TODO: how could the price fall below 1.00 when rewardsAfter was based on 9969126831808605271675?
        //      supply + rewards + 10k - tax < supply where tax = (rewards + 10k) / 10
        //      supply + (rewards + 10k) * 9 / 10 < supply
        //      because we deducted 10% of 10k as commission and it reduced the left hand side
        uint256 rewardsBefore = 9961644437442408088600;
        uint256 rewardsAfter = (10003845141667760201143 - rewardsBefore) * uint256(10) / 9;
        rewardsBefore = rewardsBefore * uint256(10) / 9 - 10_000 ether;
        run(
            10_000_000 ether,
            rewardsBefore,
            10_000 ether, // delegatedAmount
            rewardsAfter,
            30, // blocksUntil claiming
            true // initialDeposit
        );
        // staker's ZIL after claiming minus before claiming plus 18-digit claiming transaction fee
        Console.log("%s.%s%s", 99994156053341800951925 - 99894533133440243560633 + 377395241114400000);
    } 

    function test_ReproduceDevnet() public {
        uint256 rewardsBefore = 500790859951588622934;
        uint256 rewardsAfter = (532306705022011158106 - rewardsBefore) * uint256(10) / 9;
        rewardsBefore = rewardsBefore * uint256(10) / 9 - 100 ether;
        run(
            10_000_000 ether,
            rewardsBefore,
            100 ether, // delegatedAmount
            rewardsAfter,
            30, // blocksUntil claiming
            true // initialDeposit
        );
        // staker's ZIL after claiming minus before claiming plus 18-digit claiming transaction fee
        Console.log("%s.%s%s", 99994156053341800951925 - 99894533133440243560633 + 377395241114400000);
    } 

    function test_NoRewardsUnstakeAll() public {
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        run(
            10_000_000 ether, // depositAmount
            365 * 24 * 51_000 ether * depositAmount / totalDeposit, // set rewardsBefore staking
            10_000 ether, // delegatedAmount
            0, // add rewardsAfter staking
            30, // wait blocksUntil claiming
            true // initialDeposit
        );
    } 

    function test_SmallStakeSmallRewardsUnstakeAll() public {
        run(
            10_000_000 ether, // depositAmount
            690 ether, // set rewardsBefore staking
            100 ether, // delegatedAmount
            100 ether, // add rewardsAfter staking
            30, // wait blocksUntil claiming
            true // initialDeposit
        );
    } 

    function test_SmallStakeMediumRewardsUnstakeAll() public {
        run(
            10_000_000 ether, // depositAmount
            690 ether, // set rewardsBefore staking
            100 ether, // delegatedAmount
            800 ether, // add rewardsAfter staking
            30, // wait blocksUntil claiming
            true // initialDeposit
        );
    } 

    function test_SmallStakeOneYearUnstakeAll() public {
        // 7.7318% APY
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 rewardsBefore = 690 ether;
        uint256 rewardsAfter = 365 * 24 * 51_000 ether * depositAmount / totalDeposit;
        Console.log("Rewards for 1 year: %s.%s%s", rewardsAfter);
        run(
            depositAmount,
            rewardsBefore,
            100 ether, // delegatedAmount
            rewardsAfter,
            30, // blocksUntil claiming
            true // initialDeposit
        );
    } 

    function test_LargeStakeOneYearUnstakeAll() public {
        // 7.6629% APY is lower than in SmallStakeOneYearUnstakeAll
        // because the delegated amount is added to the rewards
        // and the owner receives a commission on it 
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 rewardsBefore = 690 ether;
        uint256 rewardsAfter = 365 * 24 * 51_000 ether * depositAmount / totalDeposit;
        Console.log("Rewards for 1 year: %s.%s%s", rewardsAfter);
        run(
            depositAmount,
            rewardsBefore,
            100_000 ether, // delegatedAmount
            rewardsAfter,
            30, // blocksUntil claiming
            true // initialDeposit
        );
    } 

    function test_SmallStakeLaggardOneYearUnstakeAll() public {
        // 7.1773% APY is lower than in SmallStakeOneYearUnstakeAll
        // because ??????????
        uint256 depositAmount = 10_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 rewardsBefore = 365 * 24 * 51_000 ether * depositAmount / totalDeposit;
        uint256 rewardsAfter = 365 * 24 * 51_000 ether * depositAmount / totalDeposit;
        Console.log("Rewards for 1 year: %s.%s%s", rewardsAfter);
        run(
            depositAmount,
            rewardsBefore,
            100 ether, // delegatedAmount
            rewardsAfter,
            30, // blocksUntil claiming
            true // initialDeposit
        );
    } 

    function test_SmallStakeMediumDepositOneYearUnstakeAll() public {
        // 7.7323% APY is higher than in SmallStakeOneYearUnstakeAll
        // because the delegated amount is not added to the deposit
        // i.e. it doesn't earn rewards, but the missing rewards are
        // more significant in case of a smaller deposit 
        uint256 depositAmount = 100_000_000 ether;
        uint256 totalDeposit = 5_200_000_000 ether;
        uint256 rewardsBefore = 690 ether;
        uint256 rewardsAfter = 365 * 24 * 51_000 ether * depositAmount / totalDeposit;
        Console.log("Rewards for 1 year: %s.%s%s", rewardsAfter);
        run(
            depositAmount,
            rewardsBefore,
            100 ether, // delegatedAmount
            rewardsAfter,
            30, // blocksUntil claiming
            true // initialDeposit
        );
    } 

}