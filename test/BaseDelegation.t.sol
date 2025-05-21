// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.28;

/* solhint-disable no-console */
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Deposit } from "@zilliqa/zq2/deposit_v6.sol";
import { Test } from "forge-std/Test.sol";
import { Console } from "script/Console.s.sol";
import { BaseDelegation } from "src/BaseDelegation.sol";
import { IDelegation } from "src/IDelegation.sol";
import { WithdrawalQueue } from "src/WithdrawalQueue.sol";
import { BlsVerifyPrecompile } from "test/BlsVerifyPrecompile.t.sol";

/* solhint-disable one-contract-per-file */
abstract contract BaseDelegationTest is Test {
    address payable internal proxy;
    address internal implementation;
    bytes internal initializerCall;
    bytes1 internal currentDeploymentId;
    address internal owner = 0x15fc323DFE5D5DCfbeEdc25CEcbf57f676634d77;
    address[] internal stakers = [
        0xd819fFcE7A58b1E835c25617Db7b46a00888B013,
        0x092E5E57955437876dA9Df998C96e2BE19341670,
        0xeA78aAE5Be606D2D152F00760662ac321aB8F017,
        0x6603A37980DF7ef6D44E994B3183A15D0322B7bF
    ];

    constructor() {
        for (uint256 i = 0; i < stakers.length; i++)
            assertNotEq(owner, stakers[i], "owner and staker must be different");
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
            new ERC1967Proxy(implementation, initializerCall)
        );

        storeDelegation();

        BaseDelegation delegation = BaseDelegation(
            proxy
        );

        uint256 commissionNumerator = 1_000;
        delegation.setCommissionNumerator(commissionNumerator);

        //vm.deployCodeTo("Deposit.sol", delegation.DEPOSIT_CONTRACT());
        vm.etch(
            delegation.DEPOSIT_CONTRACT(),
            address(new Deposit()).code
        );
        vm.store(delegation.DEPOSIT_CONTRACT(), bytes32(uint256(0x958a6cf6390bd7165e3519675caa670ab90f0161508a9ee714d3db7edc50740a)), bytes32(uint256(block.number / 10)));
        vm.store(delegation.DEPOSIT_CONTRACT(), bytes32(uint256(0x958a6cf6390bd7165e3519675caa670ab90f0161508a9ee714d3db7edc50740b)), bytes32(uint256(10_000_000 ether)));
        vm.store(delegation.DEPOSIT_CONTRACT(), bytes32(uint256(0x958a6cf6390bd7165e3519675caa670ab90f0161508a9ee714d3db7edc50740c)), bytes32(uint256(256)));
        vm.store(delegation.DEPOSIT_CONTRACT(), bytes32(uint256(0x958a6cf6390bd7165e3519675caa670ab90f0161508a9ee714d3db7edc50740d)), bytes32(uint256(10)));
        vm.store(delegation.DEPOSIT_CONTRACT(), bytes32(uint256(0x958a6cf6390bd7165e3519675caa670ab90f0161508a9ee714d3db7edc50740e)), bytes32(uint256(300)));
        /*
        Console.log("Deposit.minimimStake() =", Deposit(delegation.DEPOSIT_CONTRACT()).minimumStake());
        Console.log("Deposit.maximumStakers() =", Deposit(delegation.DEPOSIT_CONTRACT()).maximumStakers());
        Console.log("Deposit.blocksPerEpoch() =", Deposit(delegation.DEPOSIT_CONTRACT()).blocksPerEpoch());
        Console.log("Deposit.withdrawalPeriod() =", Deposit(delegation.DEPOSIT_CONTRACT()).withdrawalPeriod());
        //*/

        vm.etch(address(0x5a494c81), address(new BlsVerifyPrecompile()).code);

        vm.stopPrank();
    }

    enum DepositMode {Bootstrapping, Fundraising, Transforming}

    function addValidator(
        BaseDelegation delegation,
        uint256 depositAmount,
        DepositMode mode
    ) public {
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
            depositFromPool(delegation, depositAmount - (mode == DepositMode.Fundraising ? 2 : 0) * preStaked, 1);
            // wait 2 epochs for the change to the deposit to take affect
            vm.roll(block.number + Deposit(delegation.DEPOSIT_CONTRACT()).blocksPerEpoch() * 2);
        }

        if (mode == DepositMode.Transforming)
            joinPool(delegation, depositAmount, owner, 1);
    }

    function depositFromPool(
        BaseDelegation delegation,
        uint256 depositAmount,
        uint8 validatorId
    ) internal {
        vm.deal(owner, owner.balance + depositAmount);
        vm.startPrank(owner);
        bytes memory blsPubKey = bytes(hex"92fbe50544dce63cfdcc88301d7412f0edea024c91ae5d6a04c7cd3819edfc1b9d75d9121080af12e00f054d221f876c");
        blsPubKey[47] = currentDeploymentId;
        blsPubKey[0] = bytes1(validatorId);
        delegation.depositFromPool{
            value: depositAmount
        }(
            blsPubKey,
            bytes(hex"002408011220d5ed74b09dcbe84d3b32a56c01ab721cf82809848b6604535212a219d35c412f"),
            bytes(hex"b14832a866a49ddf8a3104f8ee379d29c136f29aeb8fccec9d7fb17180b99e8ed29bee2ada5ce390cb704bc6fd7f5ce814f914498376c4b8bc14841a57ae22279769ec8614e2673ba7f36edc5a4bf5733aa9d70af626279ee2b2cde939b4bd8a")
        );
        vm.stopPrank();
    }

    function joinPool(
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
        delegation.registerControlAddress(blsPubKey);
        Deposit(delegation.DEPOSIT_CONTRACT()).setControlAddress(
            blsPubKey,
            address(delegation)
        );
        //TODO: add a test in which the controlAddress calls unregisterControlAddress(blsPubKey) and makes joinPool(blsPubKey) revert
        vm.stopPrank();

        vm.startPrank(owner);
        delegation.joinPool(
            blsPubKey
        );
        vm.stopPrank();
    }

    function validator(
        uint8 validatorId
    ) internal view returns(bytes memory blsPubKey) {
        blsPubKey = bytes(hex"92fbe50544dce63cfdcc88301d7412f0edea024c91ae5d6a04c7cd3819edfc1b9d75d9121080af12e00f054d221f876c");
        blsPubKey[47] = currentDeploymentId;
        blsPubKey[0] = bytes1(validatorId);
    }

    function claimsAfterManyUnstakings(BaseDelegation delegation, uint64 steps) internal {
        uint256 i;
        uint256 x;
        uint256 min = 2 ether; // this is the minimum to avoid unstaking less than MIN_DELEGATION

        addValidator(BaseDelegation(delegation), 10_000_000 ether, DepositMode.Bootstrapping);

        // wait 2 epochs for the change to the deposit to take affect
        vm.roll(block.number + Deposit(delegation.DEPOSIT_CONTRACT()).blocksPerEpoch() * 2);

        for (i = 0; i < 4; i++) {
            vm.deal(stakers[i], 100_000 * min);
            Console.log("staker %s: %s", i+1, stakers[i]);
        }

        // rewards accrued so far
        vm.deal(address(delegation), 50_000 * min);
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
        delegation.stake{value: 2 * steps * x * min}();
        // wait 2 epochs for the change to the deposit to take affect
        vm.roll(block.number + Deposit(delegation.DEPOSIT_CONTRACT()).blocksPerEpoch() * 2);
        vm.stopPrank();
        vm.deal(address(delegation), address(delegation).balance + 10_000 * min);

        uint256 totalUnstaked;
        uint256 totalPending;
        uint256[2][] memory claims;

        for (uint256 j = 0; j < steps; j++) {
            Console.log("--------------------------------------------------------------------");
            vm.startPrank(stakers[i-1]);

            uint256 amount = delegation.unstake(x * min);
            Console.log("%s unstaked %s in block %s", stakers[i-1], amount, block.number);
            totalUnstaked += amount;

            //Console.log("block number: %s", block.number);
            Console.log("claimable: %s", delegation.getClaimable());
            claims = delegation.getPendingClaims();
            Console.log("%s pending claims:", claims.length);
            totalPending = 0;
            for (uint256 k = 0; k < claims.length; k++) {
                Console.log("%s can claim %s in block %s", stakers[i-1], claims[k][1], claims[k][0]);
                totalPending += claims[k][1];
            }
            assertEq(delegation.getClaimable() + totalPending, totalUnstaked, "claims must match unstaked amount");

            // wait 2 epochs for the change to the deposit to take affect
            vm.roll(block.number + Deposit(delegation.DEPOSIT_CONTRACT()).blocksPerEpoch() * 2);
            vm.stopPrank();
            vm.deal(address(delegation), address(delegation).balance + 10_000 * min);
        }

        vm.startPrank(stakers[i-1]);

        Console.log("--------------------------------------------------------------------");
        Console.log("block number: %s", block.number);
        Console.log("claimable: %s", delegation.getClaimable());
        claims = delegation.getPendingClaims();
        Console.log("%s pending claims:", claims.length);
        totalPending = 0;
        for (uint256 j = 0; j < claims.length; j++) {
            Console.log("%s can claim %s in block %s", stakers[i-1], claims[j][1], claims[j][0]);
            totalPending += claims[j][1];
        }
        assertEq(delegation.getClaimable() + totalPending, totalUnstaked, "claims must match unstaked amount");

        vm.roll(block.number + 100);

        Console.log("--------------------------------------------------------------------");
        Console.log("block number: %s", block.number);
        Console.log("claimable: %s", delegation.getClaimable());
        claims = delegation.getPendingClaims();
        Console.log("%s pending claims:", claims.length);
        totalPending = 0;
        for (uint256 j = 0; j < claims.length; j++) {
            Console.log("%s can claim %s in block %s", stakers[i-1], claims[j][1], claims[j][0]);
            totalPending += claims[j][1];
        }
        assertEq(delegation.getClaimable() + totalPending, totalUnstaked, "claims must match unstaked amount");

        vm.roll(block.number + delegation.unbondingPeriod());

        Console.log("--------------------------------------------------------------------");
        Console.log("block number: %s", block.number);
        Console.log("claimable: %s", delegation.getClaimable());
        claims = delegation.getPendingClaims();
        Console.log("%s pending claims:", claims.length);
        totalPending = 0;
        for (uint256 j = 0; j < claims.length; j++) {
            Console.log("%s can claim %s in block %s", stakers[i-1], claims[j][1], claims[j][0]);
            totalPending += claims[j][1];
        }
        assertEq(delegation.getClaimable() + totalPending, totalUnstaked, "claims must match unstaked amount");

        vm.stopPrank();
    }

    function getVariables(BaseDelegation delegation) internal view returns (
        uint256 nonRewards, 
        uint256 withdrawnDepositedClaims, 
        uint256 nonDepositedClaims,
        uint256 pendingRebalancedDeposit
    ) {
        nonRewards = uint256(vm.load(address(delegation), bytes32(uint256(0xc8ff0e571ef581b660c1651f85bbac921a40f9489bd04631c07fa723c13c6007))));
        withdrawnDepositedClaims = uint256(vm.load(address(delegation), bytes32(uint256(0xc8ff0e571ef581b660c1651f85bbac921a40f9489bd04631c07fa723c13c6008))));
        nonDepositedClaims = uint256(vm.load(address(delegation), bytes32(uint256(0xc8ff0e571ef581b660c1651f85bbac921a40f9489bd04631c07fa723c13c6009))));
        pendingRebalancedDeposit = uint256(vm.load(address(delegation), bytes32(uint256(0xc8ff0e571ef581b660c1651f85bbac921a40f9489bd04631c07fa723c13c6004))));
    }

    function printStatus(BaseDelegation delegation) internal view {
        (uint256 nonRewards, uint256 withdrawnDepositedClaims, uint256 nonDepositedClaims, uint256 pendingRebalancedDeposit) = getVariables(delegation);
        Console.log("withdrawnDepositedClaims  ", withdrawnDepositedClaims);
        Console.log("nonDepositedClaims        ", nonDepositedClaims);
        Console.log("pendingRebalancedDeposit  ", pendingRebalancedDeposit);
        Console.log("nonRewards                ", nonRewards);
        Console.log("balance                   ", address(delegation).balance);
        Console.log("getStake()                ", delegation.getStake());
        Console.log("getRewards()              ", delegation.getRewards());
        BaseDelegation.Validator[] memory validators = delegation.validators();
        for (uint256 i = 0; i < validators.length; i++)
            Console.log("validator-%s (%s)            %s", i, uint256(validators[i].status), validators[i].futureStake);
    }
}