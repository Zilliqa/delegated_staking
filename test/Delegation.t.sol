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
        uint256 rewardsBeforeStaking,
        uint256 taxedRewardsBeforeStaking,
        uint256 delegatedAmount,
        uint8 numberOfDelegations,
        uint256 rewardsAccruedAfterEach,
        uint256 rewardsBeforeUnstaking,
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

        vm.store(address(delegation), 0x669e9cfa685336547bc6d91346afdd259f6cd8c0cb6d0b16603b5fa60cb48804, bytes32(taxedRewardsBeforeStaking));
        vm.deal(address(delegation), rewardsBeforeStaking);
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

        uint256 ownerZILBefore;
        uint256 ownerZILAfter;
        uint256 loggedAmount;
        uint256 loggedShares;
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
            emit DelegationV2.Staked(
                staker,
                delegatedAmount,
                lst.totalSupply() * delegatedAmount / (delegation.getStake() + delegation.getRewards())
            );

            ownerZILBefore = delegation.owner().balance;

            delegation.stake{
                value: delegatedAmount
            }();

            ownerZILAfter = delegation.owner().balance;

            entries = vm.getRecordedLogs();
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

            vm.deal(address(delegation), address(delegation).balance + rewardsAccruedAfterEach);
        }

        //vm.deal(address(delegation), address(delegation).balance + rewardsEarnedUntilUnstaking);
        vm.deal(address(delegation), rewardsBeforeUnstaking);

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

    function test_1a_LargeStake_Late_NoRewards_UnstakeAll() public {
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
            30, // after unstaking wait blocksUntil claiming
            true // initialDeposit using the node owner' funds, otherwise delegated by a staker
        );
    } 

    function test_1b_LargeStake_Early_NoRewards_UnstakeAll() public {
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
            30, // after unstaking wait blocksUntil claiming
            true // initialDeposit using the node owner' funds, otherwise delegated by a staker
        );
    } 

    function test_2a_LargeStake_Late_SmallValidator_OwnDeposit_OneYearOfRewards_UnstakeAll() public {
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
            30, // after unstaking wait blocksUntil claiming
            true // initialDeposit using the node owner' funds, otherwise delegated by a staker
        );
    } 

    function test_3a_SmallStake_Late_SmallValidator_OwnDeposit_OneYearOfRewards_UnstakeAll() public {
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
            30, // after unstaking wait blocksUntil claiming
            true // initialDeposit using the node owner' funds, otherwise delegated by a staker
        );
    } 

    function test_4a_LargeStake_Late_LargeValidator_OwnDeposit_OneYearOfRewards_UnstakeAll() public {
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
            30, // after unstaking wait blocksUntil claiming
            true // initialDeposit using the node owner' funds, otherwise delegated by a staker
        );
    }

    function test_5a_SmallStake_Late_LargeValidator_OwnDeposit_OneYearOfRewards_UnstakeAll() public {
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
            30, // after unstaking wait blocksUntil claiming
            true // initialDeposit using the node owner' funds, otherwise delegated by a staker
        );
    }

    function test_2b_LargeStake_Late_SmallValidator_DelegatedDeposit_OneYearOfRewards_UnstakeAll() public {
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
            30, // after unstaking wait blocksUntil claiming
            true // initialDeposit using the node owner' funds, otherwise delegated by a staker
        );
    } 

    function test_3b_SmallStake_Late_SmallValidator_DelegatedDeposit_OneYearOfRewards_UnstakeAll() public {
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
            30, // after unstaking wait blocksUntil claiming
            false // initialDeposit using the node owner' funds, otherwise delegated by a staker
        );
    } 

    function test_4b_LargeStake_Late_LargeValidator_DelegatedDeposit_OneYearOfRewards_UnstakeAll() public {
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
            30, // after unstaking wait blocksUntil claiming
            false // initialDeposit using the node owner' funds, otherwise delegated by a staker
        );
    }

    function test_5b_SmallStake_Late_LargeValidator_DelegatedDeposit_OneYearOfRewards_UnstakeAll() public {
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
            30, // after unstaking wait blocksUntil claiming
            false // initialDeposit using the node owner' funds, otherwise delegated by a staker
        );
    }

    function test_2c_LargeStake_Early_SmallValidator_OwnDeposit_OneYearOfRewards_UnstakeAll() public {
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
            30, // after unstaking wait blocksUntil claiming
            true // initialDeposit using the node owner' funds, otherwise delegated by a staker
        );
    }

    function test_3c_SmallStake_Early_SmallValidator_OwnDeposit_OneYearOfRewards_UnstakeAll() public {
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
            30, // after unstaking wait blocksUntil claiming
            false // initialDeposit using the node owner' funds, otherwise delegated by a staker
        );
    } 

    function test_4c_LargeStake_Early_LargeValidator_OwnDeposit_OneYearOfRewards_UnstakeAll() public {
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
            30, // after unstaking wait blocksUntil claiming
            false // initialDeposit using the node owner' funds, otherwise delegated by a staker
        );
    }

    function test_5c_SmallStake_Early_LargeValidator_OwnDeposit_OneYearOfRewards_UnstakeAll() public {
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
            30, // after unstaking wait blocksUntil claiming
            false // initialDeposit using the node owner' funds, otherwise delegated by a staker
        );
    } 

    function test_6a_ManyVsOneStake_UnstakeAll() public {
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
            30, // after unstaking wait blocksUntil claiming
            true // initialDeposit using the node owner' funds, otherwise delegated by a staker
        );
    }

    function test_6b_OneVsManyStakes_UnstakeAll() public {
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
            30, // after unstaking wait blocksUntil claiming
            true // initialDeposit using the node owner' funds, otherwise delegated by a staker
        );
    }

    /*
    To compare the results of Foundry tests and a real network, use the bash scripts below
    to stake, unstake and claim on the network your local node is connected to.

    Before and after running the STAKING, UNSTAKING and CLAIMING scripts presented below,
    always execute the following bash script to capture the values needed in the Foundry test below.

    STATE:

    block=$(cast rpc eth_blockNumber --rpc-url http://localhost:4201) && \
    block_num=$(echo $block | tr -d '"' | cast to-dec --base-in 16) && \
    echo $(date +"%T,%3N") $block_num && \
    echo rewardsBeforeUnstaking = $(cast rpc eth_getBalance 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 $block --rpc-url http://localhost:4201 | tr -d '"' | cast to-dec --base-in 16) && \
    x=$(cast call 0x9e5c257D1c6dF74EaA54e58CdccaCb924669dc83 "balanceOf(address)(uint256)" 0x15fc323DFE5D5DCfbeEdc25CEcbf57f676634d77 --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
    owner_lst=$(cast to-unit $x ether) && \
    x=$(cast rpc eth_getBalance 0x15fc323DFE5D5DCfbeEdc25CEcbf57f676634d77 $block --rpc-url http://localhost:4201 | tr -d '"' | cast to-dec --base-in 16) && \
    owner_zil=$(cast to-unit $x ether) && \
    echo owner: $owner_lst LST && echo owner: $owner_zil ZIL && \
    x=$(cast call 0x9e5c257D1c6dF74EaA54e58CdccaCb924669dc83 "balanceOf(address)(uint256)" 0xd819fFcE7A58b1E835c25617Db7b46a00888B013 --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
    staker_lst=$(cast to-unit $x ether) && \
    x=$(cast rpc eth_getBalance 0xd819fFcE7A58b1E835c25617Db7b46a00888B013 $block --rpc-url http://localhost:4201 | tr -d '"' | cast to-dec --base-in 16) && \
    staker_zil=$(cast to-unit $x ether) && \
    echo staker: $staker_lst LST && echo staker: $staker_zil ZIL && \
    x=$(cast call 0x9e5c257D1c6dF74EaA54e58CdccaCb924669dc83 "totalSupply()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
    y=$(cast call 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 "getRewards()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
    z=$(cast call 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 "getStake()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && price=$(bc -l <<< \($y+$z\)/$x) && \
    echo LST price: $price && \
    echo staker LST value: $(bc -l <<< $staker_lst*$price) ZIL && \
    echo getStake = $(cast call 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 "getStake()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
    echo getRewards = $(cast call 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 "getRewards()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
    echo getTaxedRewards = $(cast call 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 "getTaxedRewards()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
    echo getTotalWithdrawals = $(cast call 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 "getTotalWithdrawals()(uint256)" --block $block_num --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g')

    STAKING: insert the private key at the end of line 1 before running the script

    forge script script/stake_Delegation.s.sol --rpc-url http://localhost:4201 --broadcast --legacy --sig "run(address payable, uint256)" 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 10000000000000000000000 --private-key 0x... && \
    block=$(cast rpc eth_blockNumber --rpc-url http://localhost:4201 | tr -d '"' | cast to-dec --base-in 16) && \
    echo rewardsAfterStaking = $(cast call 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 "getRewards()(uint256)" --block $block --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
    echo taxedRewardsAfterStaking = $(cast call 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 "getTaxedRewards()(uint256)" --block $block --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
    echo $(date +"%T,%3N") $block && \
    block=$((block-1)) && \
    echo rewardsBeforeStaking = $(cast call 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 "getRewards()(uint256)" --block $block --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
    echo taxedRewardsBeforeStaking = $(cast call 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 "getTaxedRewards()(uint256)" --block $block --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
    echo $(date +"%T,%3N") $block

    UNSTAKING: insert the private key at the end of line 1 before running the script

    forge script script/unstake_Delegation.s.sol --rpc-url http://localhost:4201 --broadcast --legacy --sig "run(address payable, uint256)" 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 0 --private-key 0x... && \
    block=$(cast rpc eth_blockNumber --rpc-url http://localhost:4201 | tr -d '"' | cast to-dec --base-in 16) && \
    echo rewardsAfterUnstaking = $(cast call 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 "getRewards()(uint256)" --block $block --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
    echo taxedRewardsAfterUnstaking = $(cast call 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 "getTaxedRewards()(uint256)" --block $block --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
    echo $(date +"%T,%3N") $block && \
    block=$((block-1)) && \
    echo rewardsBeforeUnstaking = $(cast call 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 "getRewards()(uint256)" --block $block --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
    echo taxedRewardsBeforeUnstaking = $(cast call 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 "getTaxedRewards()(uint256)" --block $block --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
    echo $(date +"%T,%3N") $block

    CLAIMING: insert the private key at the end of line 1 before running the script

    forge script script/claim_Delegation.s.sol --rpc-url http://localhost:4201 --broadcast --legacy --sig "run(address payable)" 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 --private-key 0x... -vvvv && \
    block=$(cast rpc eth_blockNumber --rpc-url http://localhost:4201 | tr -d '"' | cast to-dec --base-in 16) && \
    echo rewardsAfterClaiming = $(cast call 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 "getRewards()(uint256)" --block $block --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
    echo taxedRewardsAfterClaiming = $(cast call 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 "getTaxedRewards()(uint256)" --block $block --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
    echo $(date +"%T,%3N") $block && \
    block=$((block-1)) && \
    echo rewardsBeforeClaiming = $(cast call 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 "getRewards()(uint256)" --block $block --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
    echo taxedRewardsBeforeClaiming = $(cast call 0x7A0b7e6D24eDe78260c9ddBD98e828B0e11A8EA2 "getTaxedRewards()(uint256)" --block $block --rpc-url http://localhost:4201 | sed 's/\[[^]]*\]//g') && \
    echo $(date +"%T,%3N") $block
    */
    function test_0_ReproduceRealNetwork() public {
        uint256 delegatedAmount = 10_000 ether;
        // Insert the following values output by the STATE script below
        uint256 rewardsBeforeStaking = 197818620596390326580;
        uint256 taxedRewardsBeforeStaking = 166909461128204338052;
        // Compare the taxedRewardsAfterStaking output by the STATE script
        // with the value logged by the test below
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log("Expected taxed rewards after staking: %s.%s%s ZIL", taxedRewardsAfterStaking);
        // Insert the following value output by the UNSTAKE script
        uint256 rewardsBeforeUnstaking = 233367080700403454378;
        run(
            10_000_000 ether,
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            rewardsBeforeUnstaking,
            30, // blocksUntil claiming
            true // initialDeposit
        );
        // Replace the values below in the same order with the values output by the STATE script
        // run after the CLAIM script or logged by the CLAIM script itself
        // the staker's ZIL balance in wei according to the STATE script after claiming
        // the staker's ZIL balance in wei according to the STATE script before claiming
        // the claiming transaction fee in wei output by the CLAIM script
        Console.log("Expected staker balance after claiming: %s.%s%s ZIL",
            100_000 ether - delegatedAmount
            + 100013.464887553198739807 ether - 90013.819919979031083499 ether + 0.3897714316896 ether
        );
        // Replace the values below in the same order with values output by the STATE script
        // run before the STAKE and after the UNSTAKE scripts or logged by those script themselves
        // the owner's ZIL balance in wei according to the STATE script after unstaking
        // the owner's ZIL balance in wei according to the STATE script before staking
        // the transaction fees in wei output by the STAKING and UNSTAKING scripts
        Console.log("Actual owner commission: %s.%s%s ZIL",
            100032.696802178975738911 ether - 100025.741948627073967394 ether
            + 0.6143714334864 ether + 0.8724381022176 ether
        );
        // Compare the value logged above with the sum of the following values
        // you will see after running the test:
        // Owner commission after staking
        // Owner commission after unstaking
    }

}