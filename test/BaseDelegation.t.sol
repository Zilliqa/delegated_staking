// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.26;

/* solhint-disable no-console */
import {BlsVerifyPrecompile} from "test/BlsVerifyPrecompile.t.sol";
import {BaseDelegation} from "src/BaseDelegation.sol";
import {WithdrawalQueue} from "src/WithdrawalQueue.sol";
import {IDelegation} from "src/IDelegation.sol";
import {Deposit} from "@zilliqa/zq2/deposit_v4.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

/* solhint-disable one-contract-per-file */
abstract contract BaseDelegationTest is Test {
    address payable internal proxy;
    address internal oldImplementation;
    bytes internal initializerCall;
    address payable internal newImplementation;
    bytes internal reinitializerCall;
    bytes1 internal currentDeploymentId;
    address internal owner = 0x15fc323DFE5D5DCfbeEdc25CEcbf57f676634d77;
    address[4] internal stakers = [
        0xd819fFcE7A58b1E835c25617Db7b46a00888B013,
        0x092E5E57955437876dA9Df998C96e2BE19341670,
        0xeA78aAE5Be606D2D152F00760662ac321aB8F017,
        0x6603A37980DF7ef6D44E994B3183A15D0322B7bF
    ];

    constructor() {
        for (uint256 i = 0; i < stakers.length; i++)
            assertNotEq(owner, stakers[i], "owner and staker must be different");
        //console.log("Signer is %s", owner);
    }

    function storeDelegation() internal virtual;

    function setUp() public {
        deploy();
        deploy();
    }

    function deploy() internal {
        vm.chainId(33469);
        vm.deal(owner, 100_000 ether);
        vm.startPrank(owner);

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

        BaseDelegation oldDelegation = BaseDelegation(
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
        console.log("New implementation deployed: %s",
            newImplementation
        );
        //*/

        oldDelegation.upgradeToAndCall(
            newImplementation,
            reinitializerCall
        );

        storeDelegation();
        BaseDelegation delegation = BaseDelegation(
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

        //vm.deployCodeTo("Deposit.sol", delegation.DEPOSIT_CONTRACT());
        vm.etch(
            delegation.DEPOSIT_CONTRACT(),
            address(new Deposit()).code
        );
        vm.store(delegation.DEPOSIT_CONTRACT(), bytes32(uint256(0x958a6cf6390bd7165e3519675caa670ab90f0161508a9ee714d3db7edc50740b)), bytes32(uint256(block.number / 10)));
        vm.store(delegation.DEPOSIT_CONTRACT(), bytes32(uint256(0x958a6cf6390bd7165e3519675caa670ab90f0161508a9ee714d3db7edc50740c)), bytes32(uint256(10_000_000 ether)));
        vm.store(delegation.DEPOSIT_CONTRACT(), bytes32(uint256(0x958a6cf6390bd7165e3519675caa670ab90f0161508a9ee714d3db7edc50740d)), bytes32(uint256(256)));
        vm.store(delegation.DEPOSIT_CONTRACT(), bytes32(uint256(0x958a6cf6390bd7165e3519675caa670ab90f0161508a9ee714d3db7edc50740e)), bytes32(uint256(10)));
        /*
        console.log("Deposit.minimimStake() =", Deposit(delegation.DEPOSIT_CONTRACT()).minimumStake());
        console.log("Deposit.maximumStakers() =", Deposit(delegation.DEPOSIT_CONTRACT()).maximumStakers());
        console.log("Deposit.blocksPerEpoch() =", Deposit(delegation.DEPOSIT_CONTRACT()).blocksPerEpoch());
        //*/

        vm.etch(address(0x5a494c81), address(new BlsVerifyPrecompile()).code);

        vm.stopPrank();
    }

    enum DepositMode {Bootstrapping, Fundraising, Transforming}

    function deposit(
        BaseDelegation delegation,
        uint256 depositAmount,
        DepositMode mode
    ) internal {
        bytes memory blsPubKey;
        currentDeploymentId = bytes1(uint8(currentDeploymentId) + 1);
        uint256 preStaked = (mode == DepositMode.Fundraising) ? depositAmount / 10 : 0;
        if (mode == DepositMode.Fundraising)
            for (uint256 i = 1; i <= 2; i++) {
                vm.deal(stakers[i], stakers[i].balance + preStaked);
                vm.startPrank(stakers[i]);
                vm.expectEmit(
                    true,
                    false,
                    false,
                    false,
                    address(delegation)
                );
                emit IDelegation.Staked(
                    stakers[i],
                    preStaked,
                    ""
                );
                delegation.stake{
                    value: preStaked
                }();
                vm.stopPrank();
            }

        if (mode == DepositMode.Fundraising || mode == DepositMode.Bootstrapping) {
            vm.deal(owner, owner.balance + depositAmount - (mode == DepositMode.Fundraising ? 2 : 0) * preStaked);
            vm.startPrank(owner);
            blsPubKey = bytes(hex"01fbe50544dce63cfdcc88301d7412f0edea024c91ae5d6a04c7cd3819edfc1b9d75d9121080af12e00f054d221f876c");
            blsPubKey[47] = currentDeploymentId;
            delegation.deposit{
                value: depositAmount - (mode == DepositMode.Fundraising ? 2 : 0) * preStaked
            }(
                blsPubKey,
                bytes(hex"002408011220d5ed74b09dcbe84d3b32a56c01ab721cf82809848b6604535212a219d35c412f"),
                bytes(hex"b14832a866a49ddf8a3104f8ee379d29c136f29aeb8fccec9d7fb17180b99e8ed29bee2ada5ce390cb704bc6fd7f5ce814f914498376c4b8bc14841a57ae22279769ec8614e2673ba7f36edc5a4bf5733aa9d70af626279ee2b2cde939b4bd8a")
            );
            vm.stopPrank();

            // wait 2 epochs for the change to the deposit to take affect
            vm.roll(block.number + Deposit(delegation.DEPOSIT_CONTRACT()).blocksPerEpoch() * 2);
        }

        if (mode == DepositMode.Transforming)
            join(delegation, depositAmount, owner, 1);
    }

    function join(
        BaseDelegation delegation,
        uint256 depositAmount,
        address controlAddress,
        uint8 validatorId
    ) internal {
        vm.deal(controlAddress, controlAddress.balance + depositAmount);
        vm.startPrank(controlAddress);
        bytes memory blsPubKey = bytes(hex"92fbe50544dce63cfdcc88301d7412f0edea024c91ae5d6a04c7cd3819edfc1b9d75d9121080af12e00f054d221f876c");
        blsPubKey[47] = currentDeploymentId;
        blsPubKey[0] = bytes1(validatorId);
        Deposit(delegation.DEPOSIT_CONTRACT()).deposit{
            value: depositAmount
        }(
            blsPubKey,
            bytes(hex"002408011220d5ed74b09dcbe84d3b32a56c01ab721cf82809848b6604535212a219d35c412f"),
            bytes(hex"b14832a866a49ddf8a3104f8ee379d29c136f29aeb8fccec9d7fb17180b99e8ed29bee2ada5ce390cb704bc6fd7f5ce814f914498376c4b8bc14841a57ae22279769ec8614e2673ba7f36edc5a4bf5733aa9d70af626279ee2b2cde939b4bd8a"),
            address(0x0),
            address(0x0)
        );
        Deposit(delegation.DEPOSIT_CONTRACT()).setControlAddress(
            blsPubKey,
            address(delegation)
        );
        vm.stopPrank();

        vm.startPrank(owner);
        delegation.join(
            blsPubKey,
            controlAddress
        );
        vm.stopPrank();
    }

    function leave(
        BaseDelegation delegation,
        address controlAddress,
        uint8 validatorId
    ) internal {
        vm.startPrank(controlAddress);
        bytes memory blsPubKey = bytes(hex"92fbe50544dce63cfdcc88301d7412f0edea024c91ae5d6a04c7cd3819edfc1b9d75d9121080af12e00f054d221f876c");
        blsPubKey[47] = currentDeploymentId;
        blsPubKey[0] = bytes1(validatorId);
        delegation.leave(
            blsPubKey
        );
        vm.stopPrank();
    }

    function claimsAfterManyUnstakings(BaseDelegation delegation, uint64 steps) internal {
        uint256 i;
        uint256 x;

        deposit(BaseDelegation(delegation), 10_000_000 ether, DepositMode.Bootstrapping);

        // wait 2 epochs for the change to the deposit to take affect
        vm.roll(block.number + Deposit(delegation.DEPOSIT_CONTRACT()).blocksPerEpoch() * 2);

        for (i = 0; i < 4; i++) {
            vm.deal(stakers[i], 100_000 ether);
            console.log("staker %s: %s", i+1, stakers[i]);
        }

        // rewards accrued so far
        vm.deal(address(delegation), 50_000 ether);
        x = 50;
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
        emit IDelegation.Staked(
            stakers[i-1],
            steps * x * 1 ether,
            ""
        );
        delegation.stake{value: 2 * steps * x * 1 ether}();
        // wait 2 epochs for the change to the deposit to take affect
        vm.roll(block.number + Deposit(delegation.DEPOSIT_CONTRACT()).blocksPerEpoch() * 2);
        vm.stopPrank();
        vm.deal(address(delegation), address(delegation).balance + 10_000 ether);

        uint256 totalUnstaked;
        uint256 totalPending;
        uint256[2][] memory claims;

        for (uint256 j = 0; j < steps; j++) {
            console.log("--------------------------------------------------------------------");
            vm.startPrank(stakers[i-1]);

            uint256 amount = delegation.unstake(x * 1 ether);
            console.log("%s unstaked %s in block %s", stakers[i-1], amount, block.number);
            totalUnstaked += amount;

            //console.log("block number: %s", block.number);
            console.log("claimable: %s", delegation.getClaimable());
            claims = delegation.getPendingClaims();
            console.log("%s pending claims:", claims.length);
            totalPending = 0;
            for (uint256 k = 0; k < claims.length; k++) {
                console.log("%s can claim %s in block %s", stakers[i-1], claims[k][1], claims[k][0]);
                totalPending += claims[k][1];
            }
            assertEq(delegation.getClaimable() + totalPending, totalUnstaked, "claims must match unstaked amount");

            // wait 2 epochs for the change to the deposit to take affect
            vm.roll(block.number + Deposit(delegation.DEPOSIT_CONTRACT()).blocksPerEpoch() * 2);
            vm.stopPrank();
            vm.deal(address(delegation), address(delegation).balance + 10_000 ether);
        }

        vm.startPrank(stakers[i-1]);

        console.log("--------------------------------------------------------------------");
        console.log("block number: %s", block.number);
        console.log("claimable: %s", delegation.getClaimable());
        claims = delegation.getPendingClaims();
        console.log("%s pending claims:", claims.length);
        totalPending = 0;
        for (uint256 j = 0; j < claims.length; j++) {
            console.log("%s can claim %s in block %s", stakers[i-1], claims[j][1], claims[j][0]);
            totalPending += claims[j][1];
        }
        assertEq(delegation.getClaimable() + totalPending, totalUnstaked, "claims must match unstaked amount");

        vm.roll(block.number + 100);

        console.log("--------------------------------------------------------------------");
        console.log("block number: %s", block.number);
        console.log("claimable: %s", delegation.getClaimable());
        claims = delegation.getPendingClaims();
        console.log("%s pending claims:", claims.length);
        totalPending = 0;
        for (uint256 j = 0; j < claims.length; j++) {
            console.log("%s can claim %s in block %s", stakers[i-1], claims[j][1], claims[j][0]);
            totalPending += claims[j][1];
        }
        assertEq(delegation.getClaimable() + totalPending, totalUnstaked, "claims must match unstaked amount");

        vm.roll(block.number + WithdrawalQueue.unbondingPeriod());

        console.log("--------------------------------------------------------------------");
        console.log("block number: %s", block.number);
        console.log("claimable: %s", delegation.getClaimable());
        claims = delegation.getPendingClaims();
        console.log("%s pending claims:", claims.length);
        totalPending = 0;
        for (uint256 j = 0; j < claims.length; j++) {
            console.log("%s can claim %s in block %s", stakers[i-1], claims[j][1], claims[j][0]);
            totalPending += claims[j][1];
        }
        assertEq(delegation.getClaimable() + totalPending, totalUnstaked, "claims must match unstaked amount");

        vm.stopPrank();
    }
}