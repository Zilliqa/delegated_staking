// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

import {LiquidDelegation} from "src/LiquidDelegation.sol";
import {LiquidDelegationV2} from "src/LiquidDelegationV2.sol";
import {NonRebasingLST} from "src/NonRebasingLST.sol";
import {WithdrawalQueue} from "src/BaseDelegation.sol";
import {Delegation} from "src/Delegation.sol";
import {Deposit, InitialStaker} from "@zilliqa/zq2/deposit.sol";
import {Console} from "src/Console.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Test, Vm} from "forge-std/Test.sol";
import "forge-std/console.sol";

contract PopVerifyPrecompile {
    function popVerify(bytes memory, bytes memory) public pure returns(bool) {
        return true;
    }
}

contract LiquidDelegationTest is Test {
    address payable proxy;
    LiquidDelegationV2 delegation;
    NonRebasingLST lst;
    address owner;
    address staker = 0xd819fFcE7A58b1E835c25617Db7b46a00888B013;

    function setUp() public {
        vm.chainId(33469);
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        owner = vm.addr(deployerPrivateKey);
        //console.log("Signer is %s", owner);
        vm.deal(owner, 100_000 ether);
        vm.startPrank(owner);

        address oldImplementation = address(
            new LiquidDelegation()
        );

        bytes memory initializerCall = abi.encodeWithSelector(
            LiquidDelegation.initialize.selector,
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
        LiquidDelegation oldDelegation = LiquidDelegation(
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
            new LiquidDelegationV2()
        );
        /*
        console.log("New implementation deployed: %s",
            newImplementation
        );
        //*/
        bytes memory reinitializerCall = abi.encodeWithSelector(
            LiquidDelegationV2.reinitialize.selector
        );

        oldDelegation.upgradeToAndCall(
            newImplementation,
            reinitializerCall
        );

        delegation = LiquidDelegationV2(
                proxy
            );
        /*
        console.log("Upgraded to version: %s",
            delegation.version()
        );
        //*/
        lst = NonRebasingLST(delegation.getLST());
        /*
        console.log("LST address: %s",
            address(lst)
        );

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

        vm.etch(address(0x5a494c80), address(new PopVerifyPrecompile()).code);

        vm.stopPrank();
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
        delegation = LiquidDelegationV2(proxy);
        lst = NonRebasingLST(delegation.getLST());

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
            emit Delegation.Staked(
                staker,
                depositAmount,
                abi.encode(depositAmount)
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

        vm.store(address(delegation), 0xfa57cbed4b267d0bc9f2cbdae86b4d1d23ca818308f873af9c968a23afadfd01, bytes32(taxedRewardsBeforeStaking));
        vm.deal(address(delegation), rewardsBeforeStaking);
        vm.deal(staker, 100_000 ether);
        vm.startPrank(staker);

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
            staker.balance
        );

        Console.log("Staker balance before staking: %s.%s%s LST",
            lst.balanceOf(staker)
        );

        Console.log("Total supply before staking: %s.%s%s LST", 
            lst.totalSupply()
        );

        uint256[2] memory ownerZIL = [uint256(0), 0];
        uint256 ownerZILAfter;
        uint256 loggedAmount;
        uint256 loggedShares;
        uint256 totalShares;
        uint256 rewardsAfterStaking;
        uint256 taxedRewardsAfterStaking;
        uint256 rewardsDelta = rewardsBeforeStaking - taxedRewardsBeforeStaking;
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
            emit Delegation.Staked(
                staker,
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
                staker.balance
            );

            Console.log("Staker balance after staking: %s.%s%s LST",
                lst.balanceOf(staker)
            );

            Console.log("Total supply after staking: %s.%s%s LST",
                lst.totalSupply()
            );

            vm.deal(address(delegation), address(delegation).balance + rewardsAccruedAfterEach);
            rewardsDelta = delegation.getRewards() - taxedRewardsAfterStaking;
        }

        vm.deal(address(delegation), rewardsBeforeUnstaking);

        uint256 lstPrice = 10**18 * 1 ether * ((delegation.getStake() + delegation.getRewards() - (delegation.getRewards() - delegation.getTaxedRewards()) * delegation.getCommissionNumerator() / delegation.DENOMINATOR())) / lst.totalSupply();
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
        emit Delegation.Unstaked(
            staker,
            (delegation.getStake() + delegation.getRewards()) * lst.balanceOf(staker) / lst.totalSupply(),
            abi.encode(lst.balanceOf(staker))
        );

        uint256[2] memory stakerLST = [lst.balanceOf(staker), 0];
        ownerZIL[0] = delegation.owner().balance;

        uint256 shares = initialDeposit ? lst.balanceOf(staker) : lst.balanceOf(staker) - depositAmount;
        assertEq(totalShares, shares, "staked shares balance mismatch");

        delegation.unstake(
            shares
        );

        // wait 2 epochs for the change to the deposit to take affect
        vm.roll(block.number + Deposit(delegation.DEPOSIT_CONTRACT()).blocksPerEpoch() * 2);

        stakerLST[1] = lst.balanceOf(staker);
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

        uint256 rewardsAfterUnstaking = delegation.getRewards();
        Console.log("Rewards after unstaking: %s.%s%s ZIL",
            rewardsAfterUnstaking
        );

        uint256 taxedRewardsAfterUnstaking = delegation.getTaxedRewards();
        Console.log("Taxed rewards after unstaking: %s.%s%s ZIL",
            taxedRewardsAfterUnstaking
        );

        uint256 stakerBalanceAfterUnstaking = staker.balance;
        Console.log("Staker balance after unstaking: %s.%s%s ZIL",
            stakerBalanceAfterUnstaking
        );

        Console.log("Staker balance after unstaking: %s.%s%s LST",
            lst.balanceOf(staker)
        );

        Console.log("Total supply after unstaking: %s.%s%s LST", 
            lst.totalSupply()
        );

        vm.roll(block.number + blocksUntil);
        //TODO: remove the next line once https://github.com/Zilliqa/zq2/issues/1761 is fixed
        vm.warp(block.timestamp + blocksUntil);

        vm.recordLogs();

        uint256 unstakedAmount = loggedAmount; // the amount we logged on unstaking
        Console.log("Unstaked amount: %s.%s%s ZIL", unstakedAmount);

        vm.expectEmit(
            true,
            false,
            false,
            false,
            address(delegation)
        );
        emit Delegation.Claimed(
            staker,
            unstakedAmount,
            ""
        );

        uint256[2] memory stakerZIL = [staker.balance, 0];
        ownerZIL[0] = delegation.owner().balance;

        delegation.claim();

        stakerZIL[1] = staker.balance;
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
            staker.balance
        );
        assertEq(staker.balance, stakerBalanceAfterUnstaking + unstakedAmount, "final staker balance mismatch");

        Console.log("Staker balance after claiming: %s.%s%s LST",
            lst.balanceOf(staker)
        );

        Console.log("Total supply after claiming: %s.%s%s LST", 
            lst.totalSupply()
        );

    }

    function test_1a_LargeStake_Late_NoRewards_UnstakeAll() public {
        staker = 0x092E5E57955437876dA9Df998C96e2BE19341670;
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
            WithdrawalQueue.unbondingPeriod(), // after unstaking wait blocksUntil claiming
            true // initialDeposit using funds held by the node, otherwise delegated by a staker
        );
    } 

    //TODO: remove the test once https://github.com/Zilliqa/zq2/issues/1761 is fixed
    function test_DepositContract() public {
        vm.deal(owner, 10_000_000 ether + 1_000_000 ether + 0 ether);
        vm.deal(staker, 0);
        vm.startPrank(owner);
        Deposit(delegation.DEPOSIT_CONTRACT()).deposit{
            value: 10_000_000 ether
        }(
            bytes(hex"92fbe50544dce63cfdcc88301d7412f0edea024c91ae5d6a04c7cd3819edfc1b9d75d9121080af12e00f054d221f876c"),
            bytes(hex"002408011220d5ed74b09dcbe84d3b32a56c01ab721cf82809848b6604535212a219d35c412f"),
            bytes(hex"b14832a866a49ddf8a3104f8ee379d29c136f29aeb8fccec9d7fb17180b99e8ed29bee2ada5ce390cb704bc6fd7f5ce814f914498376c4b8bc14841a57ae22279769ec8614e2673ba7f36edc5a4bf5733aa9d70af626279ee2b2cde939b4bd8a"),
            address(staker)
        );
        console.log("validator deposited");
        console.log("validator stake: %s", Deposit(delegation.DEPOSIT_CONTRACT()).getStake(
            bytes(hex"92fbe50544dce63cfdcc88301d7412f0edea024c91ae5d6a04c7cd3819edfc1b9d75d9121080af12e00f054d221f876c")
        ));
        vm.roll(block.number + Deposit(delegation.DEPOSIT_CONTRACT()).blocksPerEpoch() * 2);
        console.log("validator stake: %s", Deposit(delegation.DEPOSIT_CONTRACT()).getStake(
            bytes(hex"92fbe50544dce63cfdcc88301d7412f0edea024c91ae5d6a04c7cd3819edfc1b9d75d9121080af12e00f054d221f876c")
        ));
        Deposit(delegation.DEPOSIT_CONTRACT()).depositTopup{
            value: 1_000_000 ether
        }();
        console.log("validator staked");
        console.log("validator stake: %s", Deposit(delegation.DEPOSIT_CONTRACT()).getStake(
            bytes(hex"92fbe50544dce63cfdcc88301d7412f0edea024c91ae5d6a04c7cd3819edfc1b9d75d9121080af12e00f054d221f876c")
        ));
        vm.roll(block.number + Deposit(delegation.DEPOSIT_CONTRACT()).blocksPerEpoch() * 2);
        console.log("validator stake: %s", Deposit(delegation.DEPOSIT_CONTRACT()).getStake(
            bytes(hex"92fbe50544dce63cfdcc88301d7412f0edea024c91ae5d6a04c7cd3819edfc1b9d75d9121080af12e00f054d221f876c")
        ));
        Deposit(delegation.DEPOSIT_CONTRACT()).unstake(
            500_000 ether
        );
        console.log("validator unstaked");
        console.log("validator stake: %s", Deposit(delegation.DEPOSIT_CONTRACT()).getStake(
            bytes(hex"92fbe50544dce63cfdcc88301d7412f0edea024c91ae5d6a04c7cd3819edfc1b9d75d9121080af12e00f054d221f876c")
        ));
        vm.roll(block.number + Deposit(delegation.DEPOSIT_CONTRACT()).blocksPerEpoch() * 2);
        console.log("validator stake: %s", Deposit(delegation.DEPOSIT_CONTRACT()).getStake(
            bytes(hex"92fbe50544dce63cfdcc88301d7412f0edea024c91ae5d6a04c7cd3819edfc1b9d75d9121080af12e00f054d221f876c")
        ));
        console.log("validator balance: %s", owner.balance);
        Deposit(delegation.DEPOSIT_CONTRACT()).withdraw();
        console.log("validator withdrew");
        console.log("validator balance: %s", owner.balance);
        //vm.roll(block.number + Deposit(delegation.DEPOSIT_CONTRACT()).withdrawalPeriod());
        //TODO: remove the next line and uncomment the previous once https://github.com/Zilliqa/zq2/issues/1761 is fixed
        vm.warp(block.timestamp + Deposit(delegation.DEPOSIT_CONTRACT()).withdrawalPeriod()); // skip(WithdrawalQueue.unbondingPeriod());
        Deposit(delegation.DEPOSIT_CONTRACT()).withdraw();
        console.log("validator withdrew again");
        console.log("validator balance: %s", owner.balance);
        vm.stopPrank();
    }

    function test_1b_LargeStake_Early_NoRewards_UnstakeAll() public {
        staker = 0x092E5E57955437876dA9Df998C96e2BE19341670;
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
            WithdrawalQueue.unbondingPeriod(), // after unstaking wait blocksUntil claiming
            true // initialDeposit using funds held by the node, otherwise delegated by a staker
        );
    } 

    function test_2a_LargeStake_Late_SmallValidator_OwnDeposit_OneYearOfRewards_UnstakeAll() public {
        staker = 0x092E5E57955437876dA9Df998C96e2BE19341670;
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
            WithdrawalQueue.unbondingPeriod(), // after unstaking wait blocksUntil claiming
            true // initialDeposit using funds held by the node, otherwise delegated by a staker
        );
    } 

    function test_3a_SmallStake_Late_SmallValidator_OwnDeposit_OneYearOfRewards_UnstakeAll() public {
        staker = 0x092E5E57955437876dA9Df998C96e2BE19341670;
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
            WithdrawalQueue.unbondingPeriod(), // after unstaking wait blocksUntil claiming
            true // initialDeposit using funds held by the node, otherwise delegated by a staker
        );
    } 

    function test_4a_LargeStake_Late_LargeValidator_OwnDeposit_OneYearOfRewards_UnstakeAll() public {
        staker = 0x092E5E57955437876dA9Df998C96e2BE19341670;
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
            WithdrawalQueue.unbondingPeriod(), // after unstaking wait blocksUntil claiming
            true // initialDeposit using funds held by the node, otherwise delegated by a staker
        );
    }

    function test_5a_SmallStake_Late_LargeValidator_OwnDeposit_OneYearOfRewards_UnstakeAll() public {
        staker = 0x092E5E57955437876dA9Df998C96e2BE19341670;
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
            WithdrawalQueue.unbondingPeriod(), // after unstaking wait blocksUntil claiming
            true // initialDeposit using funds held by the node, otherwise delegated by a staker
        );
    }

    function test_2b_LargeStake_Late_SmallValidator_DelegatedDeposit_OneYearOfRewards_UnstakeAll() public {
        staker = 0x092E5E57955437876dA9Df998C96e2BE19341670;
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
            WithdrawalQueue.unbondingPeriod(), // after unstaking wait blocksUntil claiming
            true // initialDeposit using funds held by the node, otherwise delegated by a staker
        );
    } 

    function test_3b_SmallStake_Late_SmallValidator_DelegatedDeposit_OneYearOfRewards_UnstakeAll() public {
        staker = 0x092E5E57955437876dA9Df998C96e2BE19341670;
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
            WithdrawalQueue.unbondingPeriod(), // after unstaking wait blocksUntil claiming
            false // initialDeposit using funds held by the node, otherwise delegated by a staker
        );
    } 

    function test_4b_LargeStake_Late_LargeValidator_DelegatedDeposit_OneYearOfRewards_UnstakeAll() public {
        staker = 0x092E5E57955437876dA9Df998C96e2BE19341670;
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
            WithdrawalQueue.unbondingPeriod(), // after unstaking wait blocksUntil claiming
            false // initialDeposit using funds held by the node, otherwise delegated by a staker
        );
    }

    function test_5b_SmallStake_Late_LargeValidator_DelegatedDeposit_OneYearOfRewards_UnstakeAll() public {
        staker = 0x092E5E57955437876dA9Df998C96e2BE19341670;
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
            WithdrawalQueue.unbondingPeriod(), // after unstaking wait blocksUntil claiming
            false // initialDeposit using funds held by the node, otherwise delegated by a staker
        );
    }

    function test_2c_LargeStake_Early_SmallValidator_OwnDeposit_OneYearOfRewards_UnstakeAll() public {
        staker = 0x092E5E57955437876dA9Df998C96e2BE19341670;
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
            WithdrawalQueue.unbondingPeriod(), // after unstaking wait blocksUntil claiming
            true // initialDeposit using funds held by the node, otherwise delegated by a staker
        );
    }

    function test_3c_SmallStake_Early_SmallValidator_OwnDeposit_OneYearOfRewards_UnstakeAll() public {
        staker = 0x092E5E57955437876dA9Df998C96e2BE19341670;
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
            WithdrawalQueue.unbondingPeriod(), // after unstaking wait blocksUntil claiming
            false // initialDeposit using funds held by the node, otherwise delegated by a staker
        );
    } 

    function test_4c_LargeStake_Early_LargeValidator_OwnDeposit_OneYearOfRewards_UnstakeAll() public {
        staker = 0x092E5E57955437876dA9Df998C96e2BE19341670;
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
            WithdrawalQueue.unbondingPeriod(), // after unstaking wait blocksUntil claiming
            false // initialDeposit using funds held by the node, otherwise delegated by a staker
        );
    }

    function test_5c_SmallStake_Early_LargeValidator_OwnDeposit_OneYearOfRewards_UnstakeAll() public {
        staker = 0x092E5E57955437876dA9Df998C96e2BE19341670;
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
            WithdrawalQueue.unbondingPeriod(), // after unstaking wait blocksUntil claiming
            false // initialDeposit using funds held by the node, otherwise delegated by a staker
        );
    } 

    function test_6a_ManyVsOneStake_UnstakeAll() public {
        staker = 0x092E5E57955437876dA9Df998C96e2BE19341670;
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
            WithdrawalQueue.unbondingPeriod(), // after unstaking wait blocksUntil claiming
            true // initialDeposit using funds held by the node, otherwise delegated by a staker
        );
    }

    function test_6b_OneVsManyStakes_UnstakeAll() public {
        staker = 0x092E5E57955437876dA9Df998C96e2BE19341670;
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
            WithdrawalQueue.unbondingPeriod(), // after unstaking wait blocksUntil claiming
            true // initialDeposit using funds held by the node, otherwise delegated by a staker
        );
    }

    /*
    To compare the results of Foundry tests and a real network, use the bash scripts below
    to stake, unstake and claim on the network your local node is connected to.

    Before and after running the STAKING, UNSTAKING and CLAIMING scripts presented below,
    always execute the STATE script to capture the values needed in the Foundry test below.

    STATE:
    chmod +x state.sh && ./state.sh <delegation_contract_address> <staker_address>

    STAKING:
    chmod +x stake.sh && ./stake.sh <delegation_contract_address> <staker_private_key> 10000000000000000000000

    UNSTAKING:
    chmod +x unstake.sh && ./unstake.sh <delegation_contract_address> <staker_private_key>

    CLAIMING:
    chmod +x claim.sh && ./claim.sh <delegation_contract_address> <staker_private_key>

    Before running the test, replace the address on the first line with <staker_address>
    */
    //TODO: update the values based on the devnet and fix the failing test (typo intentional)
    function est_0_ReproduceRealNetwork() public {
        staker = 0xd819fFcE7A58b1E835c25617Db7b46a00888B013;
        uint256 delegatedAmount = 10_000 ether;
        // Insert the following values output by the STATE script below
        uint256 rewardsBeforeStaking = 197818620596390326580;
        uint256 taxedRewardsBeforeStaking = 166909461128204338052;
        // Compare the taxedRewardsAfterStaking output by the STATE script
        // with the value logged by the test below
        uint256 taxedRewardsAfterStaking =
            rewardsBeforeStaking - (rewardsBeforeStaking - taxedRewardsBeforeStaking) / uint256(10);
        Console.log("Expected taxed rewards after staking: %s.%s%s ZIL", taxedRewardsAfterStaking);
        // Insert the following value output by the UNSTAKING script
        uint256 rewardsBeforeUnstaking = 233367080700403454378;
        run(
            10_000_000 ether,
            rewardsBeforeStaking,
            taxedRewardsBeforeStaking,
            delegatedAmount,
            1, // numberOfDelegations
            0, // rewardsAccruedAfterEach
            rewardsBeforeUnstaking,
            WithdrawalQueue.unbondingPeriod(), // blocksUntil claiming
            true // initialDeposit
        );
        // Replace the values below in the same order with the values output by the STATE script
        // run after the CLAIMING script or logged by the CLAIMING script itself
        // the staker's ZIL balance in wei according to the STATE script after claiming
        // the staker's ZIL balance in wei according to the STATE script before claiming
        // the claiming transaction fee in wei output by the CLAIMING script
        Console.log("Expected staker balance after claiming: %s.%s%s ZIL",
            100_000 ether - delegatedAmount
            + 100013.464887553198739807 ether - 90013.819919979031083499 ether + 0.3897714316896 ether
        );
        // Replace the values below in the same order with values output by the STATE script
        // run before the STAKING and after the UNSTAKE scripts or logged by those script themselves
        // the owner's ZIL balance in wei according to the STATE script after unstaking
        // the owner's ZIL balance in wei according to the STATE script before staking
        // the transaction fees in wei output by the STAKING and UNSTAKING scripts
        Console.log("Actual owner commission: %s.%s%s ZIL",
            uint256(
                100032.696802178975738911 ether - 100025.741948627073967394 ether
                + 0.6143714334864 ether + 0.8724381022176 ether
            )
        );
        // Compare the value logged above with the sum of the following values
        // you will see after running the test:
        // Owner commission after staking
        // Owner commission after unstaking
    }

}