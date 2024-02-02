// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import { ResourceId } from "@latticexyz/store/src/ResourceId.sol";
import { StoreSwitch } from "@latticexyz/store/src/StoreSwitch.sol";
import { World } from "@latticexyz/world/src/World.sol";
import { WorldResourceIdLib, WorldResourceIdInstance } from "@latticexyz/world/src/WorldResourceId.sol";
import { createWorld } from "@latticexyz/world/test/createWorld.sol";
import { IBaseWorld } from "@latticexyz/world/src/codegen/interfaces/IBaseWorld.sol";
import { NamespaceOwner } from "@latticexyz/world/src/codegen/tables/NamespaceOwner.sol";
import { IWorldErrors } from "@latticexyz/world/src/IWorldErrors.sol";
import { GasReporter } from "@latticexyz/gas-report/src/GasReporter.sol";

import { PuppetModule } from "../src/modules/puppet/PuppetModule.sol";
import { ERC1155Module } from "../src/modules/erc1155-puppet/ERC1155Module.sol";
import { IERC1155Mintable } from "../src/modules/erc1155-puppet/IERC1155Mintable.sol";
import { registerERC1155 } from "../src/modules/erc1155-puppet/registerERC1155.sol";
import { IERC1155Errors } from "../src/modules/erc1155-puppet/IERC1155Errors.sol";
import { IERC1155Events } from "../src/modules/erc1155-puppet/IERC1155Events.sol";
import { IERC1155Receiver } from "../src/modules/erc1155-puppet/IERC1155Receiver.sol";
import { _erc1155SystemId } from "../src/modules/erc1155-puppet/utils.sol";

abstract contract ERC1155TokenReceiver is IERC1155Receiver {
  function onERC1155Received(address, address, uint256, uint256, bytes calldata) external virtual returns (bytes4) {
    return ERC1155TokenReceiver.onERC1155Received.selector;
  }

  function onERC1155BatchReceived(
    address,
    address,
    uint256[] calldata,
    uint256[] calldata,
    bytes calldata
  ) external virtual returns (bytes4) {
    return ERC1155TokenReceiver.onERC1155BatchReceived.selector;
  }
}

contract ERC1155Recipient is ERC1155TokenReceiver {
  address public operator;
  address public from;
  uint256 public id;
  uint256 public amount;
  bytes public data;

  function onERC1155Received(
    address _operator,
    address _from,
    uint256 _id,
    uint256 _amount,
    bytes calldata _data
  ) public virtual override returns (bytes4) {
    operator = _operator;
    from = _from;
    id = _id;
    amount = _amount;
    data = _data;

    return ERC1155TokenReceiver.onERC1155Received.selector;
  }

  address public batchOperator;
  address public batchFrom;
  uint256[] internal _batchIds;
  uint256[] internal _batchAmounts;
  bytes public batchData;

  function batchIds() external view returns (uint256[] memory) {
    return _batchIds;
  }

  function batchAmounts() external view returns (uint256[] memory) {
    return _batchAmounts;
  }

  function onERC1155BatchReceived(
    address _operator,
    address _from,
    uint256[] calldata _ids,
    uint256[] calldata _amounts,
    bytes calldata _data
  ) public virtual override returns (bytes4) {
    batchOperator = _operator;
    batchFrom = _from;
    _batchIds = _ids;
    _batchAmounts = _amounts;
    batchData = _data;

    return ERC1155TokenReceiver.onERC1155BatchReceived.selector;
  }
}

contract RevertingERC1155Recipient is ERC1155Recipient {
  function onERC1155Received(
    address,
    address,
    uint256,
    uint256,
    bytes calldata
  ) public virtual override returns (bytes4) {
    revert(string(abi.encodeWithSelector(IERC1155Receiver.onERC1155Received.selector)));
  }

  function onERC1155BatchReceived(
    address,
    address,
    uint256[] calldata,
    uint256[] calldata,
    bytes calldata
  ) public virtual override returns (bytes4) {
    revert(string(abi.encodeWithSelector(IERC1155Receiver.onERC1155BatchReceived.selector)));
  }
}

contract WrongReturnDataERC1155Recipient is ERC1155Recipient {
  function onERC1155Received(
    address,
    address,
    uint256,
    uint256,
    bytes calldata
  ) public virtual override returns (bytes4) {
    return 0xCAFEBEEF;
  }

  function onERC1155BatchReceived(
    address,
    address,
    uint256[] calldata,
    uint256[] calldata,
    bytes calldata
  ) public virtual override returns (bytes4) {
    return 0xCAFEBEEF;
  }
}

contract NonERC1155Recipient {}

contract ERC1155Test is Test, GasReporter, IERC1155Events, IERC1155Errors {
  using WorldResourceIdInstance for ResourceId;

  IBaseWorld world;
  ERC1155Module erc1155Module;
  IERC1155Mintable token;

  mapping(address => mapping(uint256 => uint256)) public userMintAmounts;
  mapping(address => mapping(uint256 => uint256)) public userTransferOrBurnAmounts;

  function setUp() public {
    world = createWorld();
    world.installModule(new PuppetModule(), new bytes(0));
    StoreSwitch.setStoreAddress(address(world));

    // Register a new ERC1155 token
    token = registerERC1155(world, "myERC1155", "");
  }

  function _expectAccessDenied(address caller) internal {
    ResourceId tokenSystemId = _erc1155SystemId("myERC1155");
    vm.expectRevert(abi.encodeWithSelector(IWorldErrors.World_AccessDenied.selector, tokenSystemId.toString(), caller));
  }

  function _expectMintEvent(address operator, address to, uint256 id, uint256 amount) internal {
    _expectTransferEvent(operator, address(0), to, id, amount);
  }

  function _expectMintEvent(address operator, address to, uint256[] memory ids, uint256[] memory amounts) internal {
    _expectTransferEvent(operator, address(0), to, ids, amounts);
  }

  function _expectBurnEvent(address operator, address from, uint256 id, uint256 amount) internal {
    _expectTransferEvent(operator, from, address(0), id, amount);
  }

  function _expectBurnEvent(address operator, address from, uint256[] memory ids, uint256[] memory amounts) internal {
    _expectTransferEvent(operator, from, address(0), ids, amounts);
  }

  function _expectTransferEvent(address operator, address from, address to, uint256 id, uint256 amount) internal {
    vm.expectEmit(true, true, true, true);
    emit TransferSingle(operator, from, to, id, amount);
  }

  function _expectTransferEvent(
    address operator,
    address from,
    address to,
    uint256[] memory ids,
    uint256[] memory amounts
  ) internal {
    vm.expectEmit(true, true, true, true);
    emit TransferBatch(operator, from, to, ids, amounts);
  }

  function _assumeDifferentNonZero(address address1, address address2) internal pure {
    vm.assume(address1 != address(0));
    vm.assume(address2 != address(0));
    vm.assume(address1 != address2);
  }

  function _assumeEOA(address address1) internal view {
    uint256 toCodeSize;
    assembly {
      toCodeSize := extcodesize(address1)
    }
    vm.assume(toCodeSize == 0);
  }

  function _assumeDifferentNonZero(address address1, address address2, address address3) internal pure {
    vm.assume(address1 != address(0));
    vm.assume(address2 != address(0));
    vm.assume(address3 != address(0));
    vm.assume(address1 != address2);
    vm.assume(address2 != address3);
    vm.assume(address3 != address1);
  }

  function _getRandomArray(uint256 length) internal pure {}

  function testSetUp() public {
    assertTrue(address(token) != address(0));
    assertEq(NamespaceOwner.get(WorldResourceIdLib.encodeNamespace("myERC1155")), address(this));
  }

  function testInstallTwice() public {
    // Install the ERC1155 module again
    IERC1155Mintable anotherToken = registerERC1155(world, "anotherERC1155", "");
    assertTrue(address(anotherToken) != address(0));
    assertTrue(address(anotherToken) != address(token));
  }

  /////////////////////////////////////////////////
  // SOLADY ERC1155 TEST CAES
  // (https://github.com/Vectorized/solady/blob/main/test/ERC1155.sol)
  /////////////////////////////////////////////////

  function testAuthorizedEquivalence(address by, address from, bool isApprovedAccount) public {
    bool a = true;
    bool b = true;
    /// @solidity memory-safe-assembly
    assembly {
      if by {
        if iszero(eq(by, from)) {
          a := isApprovedAccount
        }
      }
      if iszero(or(iszero(by), eq(by, from))) {
        b := isApprovedAccount
      }
    }
    assertEq(a, b);
  }

  function testMintToEOA(address to, uint256 id, uint256 mintAmount, bytes memory mintData) public {
    _assumeEOA(to);
    vm.assume(to != address(0));

    _expectMintEvent(address(this), to, id, mintAmount);
    startGasReport("mint");
    token.mint(to, id, mintAmount, mintData);
    endGasReport();

    assertEq(token.balanceOf(to, id), mintAmount);
  }

  function testMintToERC1155Recipient(uint256 id, uint256 mintAmount, bytes memory mintData) public {
    ERC1155Recipient to = new ERC1155Recipient();

    _expectMintEvent(address(this), address(to), id, mintAmount);
    token.mint(address(to), id, mintAmount, mintData);

    assertEq(token.balanceOf(address(to), id), mintAmount);

    assertEq(to.operator(), address(this));
    assertEq(to.from(), address(0));
    assertEq(to.id(), id);
    assertEq(to.data(), mintData);
  }

  function testMintBatchToEOA(
    address to,
    uint256[] memory ids,
    uint256[] memory mintAmounts,
    bytes memory mintData
  ) public {
    _assumeEOA(to);
    vm.assume(to != address(0));
    vm.assume(ids.length > 1);
    vm.assume(ids.length <= mintAmounts.length);

    uint256 n = ids.length;

    uint256[] memory mintAmountsForCall = new uint256[](n);

    for (uint256 i = 0; i != n; i++) {
      uint256 id = ids[i];

      uint256 remainingMintAmountForId = type(uint256).max - userMintAmounts[to][id];

      uint256 mintAmount = _bound(mintAmounts[i], 0, remainingMintAmountForId);

      mintAmountsForCall[i] = mintAmount;

      userMintAmounts[to][id] += mintAmount;
    }

    _expectMintEvent(address(this), to, ids, mintAmountsForCall);
    startGasReport("mintBatch");
    token.mintBatch(to, ids, mintAmountsForCall, mintData);
    endGasReport();

    for (uint256 i = 0; i != n; i++) {
      uint256 id = ids[i];

      assertEq(token.balanceOf(to, id), userMintAmounts[to][id]);
    }
  }

  function testMintBatchToERC1155Recipient(
    uint256[] calldata ids,
    uint256[] calldata mintAmounts,
    bytes memory mintData
  ) public {
    ERC1155Recipient to = new ERC1155Recipient();
    vm.assume(ids.length > 1);
    vm.assume(ids.length <= mintAmounts.length);
    uint256 n = ids.length;

    uint256[] memory mintAmountsForCall = new uint256[](n);

    for (uint256 i = 0; i != n; i++) {
      uint256 id = ids[i];

      uint256 remainingMintAmountForId = type(uint256).max - userMintAmounts[address(to)][id];

      uint256 mintAmount = _bound(mintAmounts[i], 0, remainingMintAmountForId);

      mintAmountsForCall[i] = mintAmount;

      userMintAmounts[address(to)][id] += mintAmount;
    }

    _expectMintEvent(address(this), address(to), ids, mintAmountsForCall);
    token.mintBatch(address(to), ids, mintAmountsForCall, mintData);

    assertEq(to.batchOperator(), address(this));
    assertEq(to.batchFrom(), address(0));
    assertEq(to.batchIds(), ids);
    assertEq(to.batchAmounts(), mintAmountsForCall);
    assertEq(to.batchData(), mintData);

    for (uint256 i = 0; i != n; i++) {
      uint256 id = ids[i];

      assertEq(token.balanceOf(address(to), id), userMintAmounts[address(to)][id]);
    }
  }

  function testBurn(address to, uint256 id, uint256 mintAmount, uint256 burnAmount, bytes memory mintData) public {
    _assumeEOA(to);
    vm.assume(to != address(0));
    burnAmount = _bound(burnAmount, 0, mintAmount);

    _expectMintEvent(address(this), to, id, mintAmount);
    token.mint(to, id, mintAmount, mintData);

    vm.prank(to);
    token.setApprovalForAll(address(this), true);

    _expectBurnEvent(address(this), to, id, burnAmount);
    startGasReport("burn");
    token.burn(to, id, burnAmount);
    endGasReport();

    assertEq(token.balanceOf(to, id), mintAmount - burnAmount);
  }

  function testBurnBatch(address to, uint256[] memory ids, uint256[] memory amounts, bytes memory mintData) public {
    _assumeEOA(to);
    vm.assume(to != address(0));
    vm.assume(ids.length > 1);
    vm.assume(ids.length <= amounts.length);
    uint256 n = ids.length;

    uint256[] memory mintAmountsForCall = new uint256[](n);
    uint256[] memory burnAmountsForCall = new uint256[](n);

    for (uint256 i = 0; i != n; i++) {
      uint256 id = ids[i];

      uint256 remainingMintAmountForId = type(uint256).max - userMintAmounts[to][id];

      uint256 mintAmount = _bound(amounts[i], 0, remainingMintAmountForId);
      uint256 burnAmount = _bound(amounts[i], 0, mintAmount);

      mintAmountsForCall[i] = mintAmount;
      burnAmountsForCall[i] = burnAmount;

      userMintAmounts[to][id] += mintAmount;
      userTransferOrBurnAmounts[to][id] += burnAmount;
    }

    _expectMintEvent(address(this), to, ids, mintAmountsForCall);
    token.mintBatch(to, ids, mintAmountsForCall, mintData);

    vm.prank(to);
    token.setApprovalForAll(address(this), true);

    _expectBurnEvent(address(this), to, ids, burnAmountsForCall);
    startGasReport("burnBatch");
    token.burnBatch(to, ids, burnAmountsForCall);
    endGasReport();

    for (uint256 i = 0; i < ids.length; i++) {
      uint256 id = ids[i];

      assertEq(token.balanceOf(to, id), userMintAmounts[to][id] - userTransferOrBurnAmounts[to][id]);
    }
  }

  function testApproveAll(address to, bool approved) public {
    _assumeEOA(to);
    vm.assume(to != address(0));

    startGasReport("setApprovalForAll");
    token.setApprovalForAll(to, approved);
    endGasReport();
    assertEq(token.isApprovedForAll(address(this), to), approved);
  }

  function testSafeTransferFromToEOA(
    address operator,
    address from,
    address to,
    uint256 id,
    uint256 mintAmount,
    uint256 transferAmount,
    bytes memory mintData,
    bytes memory transferData
  ) public {
    _assumeEOA(operator);
    _assumeEOA(from);
    _assumeEOA(to);
    _assumeDifferentNonZero(operator, from, to);
    transferAmount = _bound(transferAmount, 0, mintAmount);

    _expectMintEvent(address(this), from, id, mintAmount);
    token.mint(from, id, mintAmount, mintData);

    vm.prank(from);
    token.setApprovalForAll(operator, true);

    _expectTransferEvent(operator, from, to, id, transferAmount);
    vm.prank(operator);
    startGasReport("safeTransferFrom");
    token.safeTransferFrom(from, to, id, transferAmount, transferData);
    endGasReport();

    if (to == from) {
      assertEq(token.balanceOf(to, id), mintAmount);
    } else {
      assertEq(token.balanceOf(to, id), transferAmount);
      assertEq(token.balanceOf(from, id), mintAmount - transferAmount);
    }
  }

  function testSafeTransferFromToERC1155Recipient(
    address operator,
    address from,
    uint256 id,
    uint256 mintAmount,
    uint256 transferAmount,
    bytes memory mintData,
    bytes memory transferData
  ) public {
    _assumeEOA(operator);
    _assumeEOA(from);
    _assumeDifferentNonZero(from, operator);
    transferAmount = _bound(transferAmount, 0, mintAmount);

    ERC1155Recipient to = new ERC1155Recipient();

    _expectMintEvent(address(this), from, id, mintAmount);
    token.mint(from, id, mintAmount, mintData);

    vm.prank(from);
    token.setApprovalForAll(operator, true);

    _expectTransferEvent(operator, from, address(to), id, transferAmount);
    vm.prank(operator);
    token.safeTransferFrom(from, address(to), id, transferAmount, transferData);

    assertEq(to.operator(), operator);
    assertEq(to.from(), from);
    assertEq(to.id(), id);
    assertEq(to.data(), transferData);

    assertEq(token.balanceOf(address(to), id), transferAmount);
    assertEq(token.balanceOf(from, id), mintAmount - transferAmount);
  }

  function testSafeTransferFromSelf(
    address operator,
    address to,
    uint256 id,
    uint256 mintAmount,
    uint256 transferAmount,
    bytes memory mintData,
    bytes memory transferData
  ) public {
    _assumeEOA(operator);
    _assumeEOA(to);
    _assumeDifferentNonZero(to, operator);
    transferAmount = _bound(transferAmount, 0, mintAmount);

    _expectMintEvent(address(this), operator, id, mintAmount);
    token.mint(operator, id, mintAmount, mintData);

    _expectTransferEvent(operator, operator, to, id, transferAmount);
    vm.prank(operator);
    token.safeTransferFrom(operator, to, id, transferAmount, transferData);

    assertEq(token.balanceOf(to, id), transferAmount);
    assertEq(token.balanceOf(operator, id), mintAmount - transferAmount);
  }

  function testSafeBatchTransferFromToEOA(
    address operator,
    address from,
    address to,
    uint256[] memory ids,
    uint256[] memory amounts,
    bytes memory mintData,
    bytes memory transferData
  ) public {
    _assumeEOA(operator);
    _assumeEOA(from);
    _assumeEOA(to);
    _assumeDifferentNonZero(operator, from, to);
    vm.assume(ids.length > 1);
    vm.assume(ids.length <= amounts.length);

    uint256 n = ids.length;

    uint256[] memory mintAmountsForCall = new uint256[](n);
    uint256[] memory transferAmountsForCall = new uint256[](n);

    for (uint256 i = 0; i != n; i++) {
      uint256 id = ids[i];

      uint256 remainingMintAmountForId = type(uint256).max - userMintAmounts[from][id];

      uint256 mintAmount = _bound(amounts[i], 0, remainingMintAmountForId);
      uint256 transferAmount = _bound(amounts[i], 0, mintAmount);

      mintAmountsForCall[i] = mintAmount;
      transferAmountsForCall[i] = transferAmount;

      userMintAmounts[from][id] += mintAmount;
      userTransferOrBurnAmounts[from][id] += transferAmount;
    }

    _expectMintEvent(address(this), from, ids, mintAmountsForCall);
    token.mintBatch(from, ids, mintAmountsForCall, mintData);

    vm.prank(from);
    token.setApprovalForAll(operator, true);

    _expectTransferEvent(operator, from, to, ids, transferAmountsForCall);
    vm.prank(operator);
    startGasReport("safeBatchTransferFrom");
    token.safeBatchTransferFrom(from, to, ids, transferAmountsForCall, transferData);
    endGasReport();

    for (uint256 i = 0; i != n; i++) {
      uint256 id = ids[i];

      assertEq(token.balanceOf(to, id), userTransferOrBurnAmounts[from][id]);
      assertEq(token.balanceOf(from, id), userMintAmounts[from][id] - userTransferOrBurnAmounts[from][id]);
    }
  }

  function testSafeBatchTransferFromToERC1155Recipient(
    address operator,
    address from,
    uint256[] calldata ids,
    uint256[] calldata amounts,
    bytes memory mintData,
    bytes memory transferData
  ) public {
    _assumeEOA(operator);
    _assumeEOA(from);
    _assumeDifferentNonZero(from, operator);
    vm.assume(ids.length > 1);
    vm.assume(ids.length <= amounts.length);

    ERC1155Recipient to = new ERC1155Recipient();

    uint256 n = ids.length;

    uint256[] memory mintAmountsForCall = new uint256[](n);
    uint256[] memory transferAmountsForCall = new uint256[](n);

    for (uint256 i = 0; i != n; i++) {
      uint256 id = ids[i];

      uint256 remainingMintAmountForId = type(uint256).max - userMintAmounts[from][id];

      uint256 mintAmount = _bound(amounts[i], 0, remainingMintAmountForId);
      uint256 transferAmount = _bound(amounts[i], 0, mintAmount);

      mintAmountsForCall[i] = mintAmount;
      transferAmountsForCall[i] = transferAmount;

      userMintAmounts[from][id] += mintAmount;
      userTransferOrBurnAmounts[from][id] += transferAmount;
    }

    _expectMintEvent(address(this), from, ids, mintAmountsForCall);
    token.mintBatch(from, ids, mintAmountsForCall, mintData);

    vm.prank(from);
    token.setApprovalForAll(operator, true);

    _expectTransferEvent(operator, from, address(to), ids, transferAmountsForCall);
    vm.prank(operator);
    token.safeBatchTransferFrom(from, address(to), ids, transferAmountsForCall, transferData);

    assertEq(to.batchOperator(), operator);
    assertEq(to.batchFrom(), from);
    assertEq(to.batchIds(), ids);
    assertEq(to.batchAmounts(), transferAmountsForCall);
    assertEq(to.batchData(), transferData);

    for (uint256 i = 0; i != n; i++) {
      uint256 id = ids[i];
      uint256 transferAmount = userTransferOrBurnAmounts[from][id];

      assertEq(token.balanceOf(address(to), id), transferAmount);
      assertEq(token.balanceOf(from, id), userMintAmounts[from][id] - transferAmount);
    }
  }

  function testBatchBalanceOf(
    address to,
    uint256[] memory ids,
    uint256[] memory mintAmounts,
    bytes memory mintData
  ) public {
    _assumeEOA(to);
    vm.assume(to != address(0));
    vm.assume(ids.length > 1);
    vm.assume(ids.length <= mintAmounts.length);
    uint256 n = ids.length;

    address[] memory tos = new address[](n);

    for (uint256 i = 0; i != n; i++) {
      uint256 id = ids[i];
      uint256 remainingMintAmountForId = type(uint256).max - userMintAmounts[to][id];

      tos[i] = to;

      uint256 mintAmount = _bound(mintAmounts[i], 0, remainingMintAmountForId);

      token.mint(to, id, mintAmount, mintData);

      userMintAmounts[to][id] += mintAmount;
    }

    uint256[] memory balances = token.balanceOfBatch(tos, ids);

    for (uint256 i = 0; i != n; i++) {
      assertEq(balances[i], token.balanceOf(tos[i], ids[i]));
    }
  }

  function testMintToZeroReverts(uint256 id, uint256 mintAmount, bytes memory mintData) public {
    vm.expectRevert(abi.encodeWithSelector(ERC1155InvalidReceiver.selector, address(0)));
    token.mint(address(0), id, mintAmount, mintData);
  }

  function testMintToNonERC155RecipientReverts(uint256 id, uint256 mintAmount, bytes memory mintData) public {
    address to = address(new NonERC1155Recipient());
    vm.expectRevert(abi.encodeWithSelector(ERC1155InvalidReceiver.selector, to));
    token.mint(to, id, mintAmount, mintData);
  }

  function testMintToRevertingERC155RecipientReverts(uint256 id, uint256 mintAmount, bytes memory mintData) public {
    address to = address(new RevertingERC1155Recipient());
    vm.expectRevert(abi.encodeWithSelector(ERC1155TokenReceiver.onERC1155Received.selector));
    token.mint(to, id, mintAmount, mintData);
  }

  function testMintToWrongReturnDataERC155RecipientReverts(
    uint256 id,
    uint256 mintAmount,
    bytes memory mintData
  ) public {
    address to = address(new WrongReturnDataERC1155Recipient());
    vm.expectRevert(abi.encodeWithSelector(ERC1155InvalidReceiver.selector, to));
    token.mint(to, id, mintAmount, mintData);
  }

  function testBurnInsufficientBalanceReverts(
    address to,
    uint256 id,
    uint256 mintAmount,
    uint256 burnAmount,
    bytes memory mintData
  ) public {
    _assumeEOA(to);
    vm.assume(to != address(0));
    vm.assume(mintAmount < type(uint256).max);
    burnAmount = _bound(burnAmount, mintAmount + 1, type(uint256).max);

    token.mint(to, id, mintAmount, mintData);

    vm.prank(to);
    token.setApprovalForAll(address(this), true);

    vm.expectRevert(abi.encodeWithSelector(ERC1155InsufficientBalance.selector, to, mintAmount, burnAmount, id));
    token.burn(to, id, burnAmount);
  }

  function testSafeTransferFromInsufficientBalanceReverts(
    address operator,
    address from,
    address to,
    uint256 id,
    uint256 mintAmount,
    uint256 transferAmount,
    bytes memory mintData,
    bytes memory transferData
  ) public {
    _assumeEOA(operator);
    _assumeEOA(from);
    _assumeEOA(to);
    _assumeDifferentNonZero(operator, from, to);
    vm.assume(mintAmount < type(uint256).max);
    transferAmount = _bound(transferAmount, mintAmount + 1, type(uint256).max);

    token.mint(from, id, mintAmount, mintData);

    vm.prank(from);
    token.setApprovalForAll(operator, true);

    vm.expectRevert(abi.encodeWithSelector(ERC1155InsufficientBalance.selector, from, mintAmount, transferAmount, id));
    vm.prank(operator);
    token.safeTransferFrom(from, to, id, transferAmount, transferData);
  }

  function testSafeTransferFromSelfInsufficientBalanceReverts(
    address operator,
    address to,
    uint256 id,
    uint256 mintAmount,
    uint256 transferAmount,
    bytes memory mintData,
    bytes memory transferData
  ) public {
    _assumeEOA(operator);
    _assumeEOA(to);
    _assumeDifferentNonZero(to, operator);
    vm.assume(mintAmount < type(uint256).max);
    transferAmount = _bound(transferAmount, mintAmount + 1, type(uint256).max);

    token.mint(operator, id, mintAmount, mintData);

    vm.expectRevert(
      abi.encodeWithSelector(ERC1155InsufficientBalance.selector, operator, mintAmount, transferAmount, id)
    );
    vm.prank(operator);
    token.safeTransferFrom(operator, to, id, transferAmount, transferData);
  }

  function testSafeTransferFromToZeroReverts(
    address operator,
    uint256 id,
    uint256 mintAmount,
    uint256 transferAmount,
    bytes memory mintData,
    bytes memory transferData
  ) public {
    _assumeEOA(operator);
    vm.assume(operator != address(0));

    transferAmount = _bound(transferAmount, 0, mintAmount);

    token.mint(operator, id, mintAmount, mintData);

    vm.expectRevert(abi.encodeWithSelector(ERC1155InvalidReceiver.selector, address(0)));
    vm.prank(operator);
    token.safeTransferFrom(operator, address(0), id, transferAmount, transferData);
  }

  function testSafeTransferFromToNonERC155RecipientReverts(
    address operator,
    uint256 id,
    uint256 mintAmount,
    uint256 transferAmount,
    bytes memory mintData,
    bytes memory transferData
  ) public {
    _assumeEOA(operator);
    vm.assume(operator != address(0));
    transferAmount = _bound(transferAmount, 0, mintAmount);

    token.mint(operator, id, mintAmount, mintData);
    address to = address(new NonERC1155Recipient());

    vm.expectRevert(abi.encodeWithSelector(ERC1155InvalidReceiver.selector, to));
    vm.prank(operator);
    token.safeTransferFrom(operator, to, id, transferAmount, transferData);
  }

  function testSafeTransferFromToRevertingERC1155RecipientReverts(
    address operator,
    uint256 id,
    uint256 mintAmount,
    uint256 transferAmount,
    bytes memory mintData,
    bytes memory transferData
  ) public {
    _assumeEOA(operator);
    vm.assume(operator != address(0));
    transferAmount = _bound(transferAmount, 0, mintAmount);

    token.mint(operator, id, mintAmount, mintData);
    RevertingERC1155Recipient to = new RevertingERC1155Recipient();

    vm.expectRevert(abi.encodeWithSelector(ERC1155TokenReceiver.onERC1155Received.selector));
    vm.prank(operator);
    token.safeTransferFrom(operator, address(to), id, transferAmount, transferData);
  }

  function testSafeTransferFromToWrongReturnDataERC1155RecipientReverts(
    address operator,
    uint256 id,
    uint256 mintAmount,
    uint256 transferAmount,
    bytes memory mintData,
    bytes memory transferData
  ) public {
    _assumeEOA(operator);
    vm.assume(operator != address(0));
    transferAmount = _bound(transferAmount, 0, mintAmount);

    token.mint(operator, id, mintAmount, mintData);
    address to = address(new WrongReturnDataERC1155Recipient());

    vm.expectRevert(abi.encodeWithSelector(ERC1155InvalidReceiver.selector, address(to)));
    vm.prank(operator);
    token.safeTransferFrom(operator, to, id, transferAmount, transferData);
  }

  function testSafeBatchTransferInsufficientBalanceReverts(
    address operator,
    address from,
    address to,
    uint256[] calldata ids,
    uint256[] calldata amounts,
    bytes memory mintData,
    bytes memory transferData
  ) public {
    _assumeEOA(operator);
    _assumeEOA(from);
    _assumeEOA(to);
    _assumeDifferentNonZero(operator, from, to);
    vm.assume(ids.length > 1);
    vm.assume(ids.length <= amounts.length);

    uint256 n = ids.length;

    uint256[] memory mintAmountsForCall = new uint256[](n);
    uint256[] memory transferAmountsForCall = new uint256[](n);

    for (uint256 i = 0; i != n; i++) {
      uint256 id = ids[i];

      uint256 remainingMintAmountForId = type(uint256).max - userMintAmounts[from][id];

      uint256 mintAmount = _bound(amounts[i], 0, remainingMintAmountForId);
      if (mintAmount == type(uint256).max) return;
      uint256 transferAmount = _bound(amounts[i], mintAmount + 1, type(uint256).max);

      mintAmountsForCall[i] = mintAmount;
      transferAmountsForCall[i] = transferAmount;

      userMintAmounts[from][id] += mintAmount;
    }

    token.mintBatch(from, ids, mintAmountsForCall, mintData);

    vm.prank(from);
    token.setApprovalForAll(operator, true);

    uint256 insufficientId;
    for (uint256 i = 0; i != n; i++) {
      if (userMintAmounts[from][ids[i]] < transferAmountsForCall[i]) {
        insufficientId = i;
        break;
      }
      userMintAmounts[from][ids[i]] -= transferAmountsForCall[i];
    }

    vm.expectRevert(
      abi.encodeWithSelector(
        ERC1155InsufficientBalance.selector,
        from,
        userMintAmounts[from][ids[insufficientId]],
        transferAmountsForCall[insufficientId],
        ids[insufficientId]
      )
    );
    vm.prank(operator);
    token.safeBatchTransferFrom(from, to, ids, transferAmountsForCall, transferData);
  }

  function testSafeBatchTransferFromToZeroReverts(
    address operator,
    address from,
    uint256[] calldata ids,
    uint256[] calldata amounts,
    bytes memory mintData,
    bytes memory transferData
  ) public {
    _assumeEOA(operator);
    _assumeEOA(operator);
    _assumeDifferentNonZero(operator, from);
    vm.assume(ids.length > 0);
    vm.assume(ids.length <= amounts.length);

    uint256 n = ids.length;

    uint256[] memory mintAmountsForCall = new uint256[](n);
    uint256[] memory transferAmountsForCall = new uint256[](n);

    for (uint256 i = 0; i != n; i++) {
      uint256 id = ids[i];

      uint256 remainingMintAmountForId = type(uint256).max - userMintAmounts[from][id];

      uint256 mintAmount = _bound(amounts[i], 0, remainingMintAmountForId);
      uint256 transferAmount = _bound(amounts[i], 0, mintAmount);

      mintAmountsForCall[i] = mintAmount;
      transferAmountsForCall[i] = transferAmount;

      userMintAmounts[from][id] += mintAmount;
    }

    token.mintBatch(from, ids, mintAmountsForCall, mintData);

    vm.prank(from);
    token.setApprovalForAll(operator, true);

    vm.expectRevert(abi.encodeWithSelector(ERC1155InvalidReceiver.selector, address(0)));
    vm.prank(operator);
    token.safeBatchTransferFrom(from, address(0), ids, transferAmountsForCall, transferData);
  }

  function testSafeBatchTransferFromToNonERC1155RecipientReverts(
    address operator,
    address from,
    uint256[] calldata ids,
    uint256[] calldata amounts,
    bytes memory mintData,
    bytes memory transferData
  ) public {
    _assumeEOA(operator);
    _assumeEOA(from);
    _assumeDifferentNonZero(from, operator);
    vm.assume(ids.length > 1);
    vm.assume(ids.length <= amounts.length);

    uint256 n = ids.length;

    uint256[] memory mintAmountsForCall = new uint256[](n);
    uint256[] memory transferAmountsForCall = new uint256[](n);

    for (uint256 i = 0; i != n; i++) {
      uint256 id = ids[i];

      uint256 remainingMintAmountForId = type(uint256).max - userMintAmounts[from][id];

      uint256 mintAmount = _bound(amounts[i], 0, remainingMintAmountForId);
      uint256 transferAmount = _bound(amounts[i], 0, mintAmount);

      mintAmountsForCall[i] = mintAmount;
      transferAmountsForCall[i] = transferAmount;

      userMintAmounts[from][id] += mintAmount;
    }

    token.mintBatch(from, ids, mintAmountsForCall, mintData);

    vm.prank(from);
    token.setApprovalForAll(operator, true);

    address to = address(new NonERC1155Recipient());

    vm.expectRevert(abi.encodeWithSelector(ERC1155InvalidReceiver.selector, to));
    vm.prank(operator);
    token.safeBatchTransferFrom(from, to, ids, transferAmountsForCall, transferData);
  }

  function testSafeBatchTransferFromToRevertingERC1155RecipientReverts(
    address operator,
    address from,
    uint256[] calldata ids,
    uint256[] calldata amounts,
    bytes memory mintData,
    bytes memory transferData
  ) public {
    _assumeEOA(operator);
    _assumeEOA(from);
    _assumeDifferentNonZero(from, operator);
    vm.assume(ids.length > 1);
    vm.assume(ids.length <= amounts.length);

    uint256 n = ids.length;

    uint256[] memory mintAmountsForCall = new uint256[](n);
    uint256[] memory transferAmountsForCall = new uint256[](n);

    for (uint256 i = 0; i != n; i++) {
      uint256 id = ids[i];

      uint256 remainingMintAmountForId = type(uint256).max - userMintAmounts[from][id];

      uint256 mintAmount = _bound(amounts[i], 0, remainingMintAmountForId);
      uint256 transferAmount = _bound(amounts[i], 0, mintAmount);

      mintAmountsForCall[i] = mintAmount;
      transferAmountsForCall[i] = transferAmount;

      userMintAmounts[from][id] += mintAmount;
    }

    token.mintBatch(from, ids, mintAmountsForCall, mintData);

    vm.prank(from);
    token.setApprovalForAll(operator, true);

    address to = address(new RevertingERC1155Recipient());

    vm.expectRevert(abi.encodeWithSelector(ERC1155TokenReceiver.onERC1155BatchReceived.selector));
    vm.prank(operator);
    token.safeBatchTransferFrom(from, to, ids, transferAmountsForCall, transferData);
  }

  function testSafeBatchTransferFromToWrongReturnDataERC1155RecipientReverts(
    address operator,
    address from,
    uint256[] calldata ids,
    uint256[] calldata amounts,
    bytes memory mintData,
    bytes memory transferData
  ) public {
    _assumeEOA(operator);
    _assumeEOA(from);
    _assumeDifferentNonZero(from, operator);
    vm.assume(ids.length > 1);
    vm.assume(ids.length <= amounts.length);

    uint256 n = ids.length;

    uint256[] memory mintAmountsForCall = new uint256[](n);
    uint256[] memory transferAmountsForCall = new uint256[](n);

    for (uint256 i = 0; i != n; i++) {
      uint256 id = ids[i];

      uint256 remainingMintAmountForId = type(uint256).max - userMintAmounts[from][id];

      uint256 mintAmount = _bound(amounts[i], 0, remainingMintAmountForId);
      uint256 transferAmount = _bound(amounts[i], 0, mintAmount);

      mintAmountsForCall[i] = mintAmount;
      transferAmountsForCall[i] = transferAmount;

      userMintAmounts[from][id] += mintAmount;
    }

    token.mintBatch(from, ids, mintAmountsForCall, mintData);

    vm.prank(from);
    token.setApprovalForAll(operator, true);

    address to = address(new WrongReturnDataERC1155Recipient());

    vm.expectRevert(abi.encodeWithSelector(ERC1155InvalidReceiver.selector, to));
    vm.prank(operator);
    token.safeBatchTransferFrom(from, to, ids, transferAmountsForCall, transferData);
  }

  function testSafeBatchTransferFromWithArrayLengthMismatchReverts(
    address operator,
    address from,
    address to,
    uint256[] calldata ids,
    uint256[] calldata amounts,
    bytes memory mintData,
    bytes memory transferData
  ) public {
    _assumeEOA(operator);
    _assumeEOA(from);
    _assumeEOA(to);
    _assumeDifferentNonZero(from, to, operator);
    vm.assume(ids.length != amounts.length);

    if (ids.length == amounts.length) return;

    vm.expectRevert(abi.encodeWithSelector(ERC1155InvalidArrayLength.selector, ids.length, amounts.length));
    token.mintBatch(from, ids, amounts, mintData);

    vm.prank(from);
    token.setApprovalForAll(operator, true);

    vm.expectRevert(abi.encodeWithSelector(ERC1155InvalidArrayLength.selector, ids.length, amounts.length));
    vm.prank(operator);
    token.safeBatchTransferFrom(from, to, ids, amounts, transferData);
  }

  function testMintBatchToZeroReverts(
    address operator,
    address from,
    uint256[] calldata ids,
    uint256[] calldata mintAmounts,
    bytes memory mintData
  ) public {
    _assumeDifferentNonZero(operator, from);
    vm.assume(ids.length <= mintAmounts.length);

    uint256 n = ids.length;

    uint256[] memory mintAmountsForCall = new uint256[](n);
    for (uint256 i = 0; i != n; i++) {
      uint256 id = ids[i];

      uint256 remainingMintAmountForId = type(uint256).max - userMintAmounts[address(0)][id];

      uint256 mintAmount = _bound(mintAmounts[i], 0, remainingMintAmountForId);

      mintAmountsForCall[i] = mintAmount;

      userMintAmounts[address(0)][id] += mintAmount;
    }

    vm.expectRevert(abi.encodeWithSelector(ERC1155InvalidReceiver.selector, address(0)));
    token.mintBatch(address(0), ids, mintAmountsForCall, mintData);
  }

  function testMintBatchToNonERC1155RecipientReverts(
    address operator,
    address from,
    uint256[] calldata ids,
    uint256[] calldata mintAmounts,
    bytes memory mintData
  ) public {
    _assumeDifferentNonZero(operator, from);
    vm.assume(ids.length > 1);
    vm.assume(ids.length <= mintAmounts.length);

    uint256 n = ids.length;

    uint256[] memory mintAmountsForCall = new uint256[](n);

    address to = address(new NonERC1155Recipient());

    for (uint256 i = 0; i != n; i++) {
      uint256 id = ids[i];

      uint256 remainingMintAmountForId = type(uint256).max - userMintAmounts[to][id];

      uint256 mintAmount = _bound(mintAmounts[i], 0, remainingMintAmountForId);

      mintAmountsForCall[i] = mintAmount;

      userMintAmounts[to][id] += mintAmount;
    }

    vm.expectRevert(abi.encodeWithSelector(ERC1155InvalidReceiver.selector, to));
    token.mintBatch(to, ids, mintAmountsForCall, mintData);
  }

  function testMintBatchToRevertingERC1155RecipientReverts(
    address operator,
    address from,
    uint256[] calldata ids,
    uint256[] calldata mintAmounts,
    bytes memory mintData
  ) public {
    _assumeDifferentNonZero(operator, from);
    vm.assume(ids.length > 1);
    vm.assume(ids.length <= mintAmounts.length);

    uint256 n = ids.length;

    uint256[] memory mintAmountsForCall = new uint256[](n);

    address to = address(new RevertingERC1155Recipient());

    for (uint256 i = 0; i != n; i++) {
      uint256 id = ids[i];

      uint256 remainingMintAmountForId = type(uint256).max - userMintAmounts[to][id];

      uint256 mintAmount = _bound(mintAmounts[i], 0, remainingMintAmountForId);

      mintAmountsForCall[i] = mintAmount;

      userMintAmounts[to][id] += mintAmount;
    }

    vm.expectRevert(abi.encodeWithSelector(ERC1155TokenReceiver.onERC1155BatchReceived.selector));
    token.mintBatch(to, ids, mintAmountsForCall, mintData);
  }

  function testMintBatchToWrongReturnDataERC1155RecipientReverts(
    address from,
    uint256[] calldata ids,
    uint256[] calldata mintAmounts,
    bytes memory mintData
  ) public {
    _assumeEOA(from);
    vm.assume(from != address(0));
    vm.assume(ids.length > 1);
    vm.assume(ids.length <= mintAmounts.length);

    uint256 n = ids.length;

    uint256[] memory mintAmountsForCall = new uint256[](n);

    address to = address(new WrongReturnDataERC1155Recipient());

    for (uint256 i = 0; i != n; i++) {
      uint256 id = ids[i];

      uint256 remainingMintAmountForId = type(uint256).max - userMintAmounts[to][id];

      uint256 mintAmount = _bound(mintAmounts[i], 0, remainingMintAmountForId);

      mintAmountsForCall[i] = mintAmount;

      userMintAmounts[to][id] += mintAmount;
    }

    vm.expectRevert(abi.encodeWithSelector(ERC1155InvalidReceiver.selector, to));
    token.mintBatch(to, ids, mintAmountsForCall, mintData);
  }

  function testMintBatchWithArrayMismatchReverts(
    address to,
    uint256[] calldata ids,
    uint256[] calldata mintAmounts,
    bytes memory mintData
  ) public {
    vm.assume(to != address(0));
    vm.assume(ids.length != mintAmounts.length);

    vm.expectRevert(abi.encodeWithSelector(ERC1155InvalidArrayLength.selector, ids.length, mintAmounts.length));
    token.mintBatch(to, ids, mintAmounts, mintData);
  }

  function testBurnBatchInsufficientBalanceReverts(
    address to,
    uint256[] calldata ids,
    uint256[] calldata mintAmounts,
    uint256[] calldata burnAmounts,
    bytes memory mintData
  ) public {
    _assumeEOA(to);
    vm.assume(to != address(0));
    vm.assume(ids.length > 1);
    vm.assume(ids.length <= mintAmounts.length);
    vm.assume(ids.length <= burnAmounts.length);

    uint256 n = ids.length;

    uint256[] memory mintAmountsForCall = new uint256[](n);
    uint256[] memory burnAmountsForCall = new uint256[](n);

    for (uint256 i = 0; i != n; i++) {
      uint256 id = ids[i];

      uint256 remainingMintAmountForId = type(uint256).max - userMintAmounts[to][id];

      uint256 mintAmount = _bound(mintAmounts[i], 0, remainingMintAmountForId);
      if (mintAmount == type(uint256).max) return;
      uint256 burnAmount = _bound(burnAmounts[i], mintAmount + 1, type(uint256).max);

      mintAmountsForCall[i] = mintAmount;
      burnAmountsForCall[i] = burnAmount;

      userMintAmounts[to][id] += mintAmount;
    }

    token.mintBatch(to, ids, mintAmountsForCall, mintData);

    vm.prank(to);
    token.setApprovalForAll(address(this), true);

    uint256 insufficientId;
    for (uint256 i = 0; i != n; i++) {
      if (userMintAmounts[to][ids[i]] < burnAmountsForCall[i]) {
        insufficientId = i;
        break;
      }
      userMintAmounts[to][ids[i]] -= burnAmountsForCall[i];
    }

    vm.expectRevert(
      abi.encodeWithSelector(
        ERC1155InsufficientBalance.selector,
        to,
        userMintAmounts[to][ids[insufficientId]],
        burnAmountsForCall[insufficientId],
        ids[insufficientId]
      )
    );
    token.burnBatch(to, ids, burnAmountsForCall);
  }

  function testBurnBatchWithArrayLengthMismatchReverts(
    address to,
    uint256[] calldata ids,
    uint256[] calldata burnAmounts
  ) public {
    _assumeEOA(to);
    vm.assume(to != address(0));
    vm.assume(ids.length != burnAmounts.length);

    vm.prank(to);
    token.setApprovalForAll(address(this), true);

    vm.expectRevert(abi.encodeWithSelector(ERC1155InvalidArrayLength.selector, ids.length, burnAmounts.length));
    token.burnBatch(to, ids, burnAmounts);
  }

  function testBalanceOfBatchWithArrayMismatchReverts(address[] calldata tos, uint256[] calldata ids) public {
    vm.assume(tos.length != ids.length);

    vm.expectRevert(abi.encodeWithSelector(ERC1155InvalidArrayLength.selector, ids.length, tos.length));
    token.balanceOfBatch(tos, ids);
  }

  function testMintGas() public {
    testMintToEOA(address(0xABCD), 1e18, 1, "");
  }

  function testBatchMintGas() public {
    uint256[] memory ids = new uint256[](2);
    ids[0] = uint256(1e18);
    ids[1] = uint256(2e18);

    uint256[] memory amounts = new uint256[](2);
    amounts[0] = 1;
    amounts[1] = 2;

    testMintBatchToEOA(address(0xABCD), ids, amounts, "");
  }

  function testBurnGas() public {
    testBurn(address(0xABCD), 1e18, 1, 1, "");
  }

  function testBatchBurnGas() public {
    uint256[] memory ids = new uint256[](2);
    ids[0] = uint256(1e18);
    ids[1] = uint256(2e18);

    uint256[] memory amounts = new uint256[](2);
    amounts[0] = 1;
    amounts[1] = 2;

    testBurnBatch(address(0xABCD), ids, amounts, "");
  }

  function testApproveAllGas() public {
    testApproveAll(address(0xABCD), true);
  }

  function testSafeTransferFromToEOAGas() public {
    testSafeTransferFromToEOA(address(0xABCD), address(0xBEEF), address(0xDEFE), 1e18, 1, 1, "", "");
  }

  function testSafeBatchTransferFromToEOAGas() public {
    uint256[] memory ids = new uint256[](2);
    ids[0] = uint256(1e18);
    ids[1] = uint256(2e18);

    uint256[] memory amounts = new uint256[](2);
    amounts[0] = 1;
    amounts[1] = 2;

    testSafeBatchTransferFromToEOA(address(0xABCD), address(0xBEEF), address(0xDEFE), ids, amounts, "", "");
  }
}
