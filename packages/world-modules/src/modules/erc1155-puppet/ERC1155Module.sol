// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import { ResourceIds } from "@latticexyz/store/src/codegen/tables/ResourceIds.sol";
import { ResourceId } from "@latticexyz/store/src/ResourceId.sol";
import { Module } from "@latticexyz/world/src/Module.sol";
import { WorldResourceIdLib } from "@latticexyz/world/src/WorldResourceId.sol";
import { IBaseWorld } from "@latticexyz/world/src/codegen/interfaces/IBaseWorld.sol";
import { InstalledModules } from "@latticexyz/world/src/codegen/tables/InstalledModules.sol";
import { revertWithBytes } from "@latticexyz/world/src/revertWithBytes.sol";

import { Puppet } from "../puppet/Puppet.sol";
import { createPuppet } from "../puppet/createPuppet.sol";

import { MODULE_NAME, MODULE_NAMESPACE, MODULE_NAMESPACE_ID, ERC1155_REGISTRY_TABLE_ID } from "./constants.sol";
import { _erc1155SystemId, _balancesTableId, _metadataURITableId, _operatorApprovalTableId } from "./utils.sol";
import { ERC1155System } from "./ERC1155System.sol";

import { ERC1155OperatorApproval } from "./tables/ERC1155OperatorApproval.sol";
import { ERC1155Registry } from "./tables/ERC1155Registry.sol";
import { ERC1155Balances } from "./tables/ERC1155Balances.sol";
import { ERC1155MetadataURI } from "./tables/ERC1155MetadataURI.sol";

contract ERC1155Module is Module {
  error ERC1155Module_InvalidNamespace(bytes14 namespace);

  address immutable registrationLibrary = address(new ERC1155ModuleRegistrationLibrary());

  function install(bytes memory encodedArgs) public {
    // Require the module to not be installed with these args yet
    requireNotInstalled(__self, encodedArgs);

    // Decode args
    (bytes14 namespace, string memory uri) = abi.decode(encodedArgs, (bytes14, string));

    // Require the namespace to not be the module's namespace
    if (namespace == MODULE_NAMESPACE) {
      revert ERC1155Module_InvalidNamespace(namespace);
    }

    // Register the ERC1155 tables and system
    IBaseWorld world = IBaseWorld(_world());
    (bool success, bytes memory returnData) = registrationLibrary.delegatecall(
      abi.encodeCall(ERC1155ModuleRegistrationLibrary.register, (world, namespace))
    );
    if (!success) revertWithBytes(returnData);

    // Initialize the Metadata uri
    ERC1155MetadataURI.set(_metadataURITableId(namespace), uri);

    // Deploy and register the ERC1155 puppet.
    ResourceId erc1155SystemId = _erc1155SystemId(namespace);
    address puppet = createPuppet(world, erc1155SystemId);

    // Transfer ownership of the namespace to the caller
    ResourceId namespaceId = WorldResourceIdLib.encodeNamespace(namespace);
    world.transferOwnership(namespaceId, _msgSender());

    // Register the ERC1155 in the ERC20Registry
    if (!ResourceIds.getExists(ERC1155_REGISTRY_TABLE_ID)) {
      world.registerNamespace(MODULE_NAMESPACE_ID);
      ERC1155Registry.register(ERC1155_REGISTRY_TABLE_ID);
    }
    ERC1155Registry.set(ERC1155_REGISTRY_TABLE_ID, namespaceId, puppet);
  }

  function installRoot(bytes memory) public pure {
    revert Module_RootInstallNotSupported();
  }
}

contract ERC1155ModuleRegistrationLibrary {
  /**
   * Register systems and tables for a new ERC1155 token in a given namespace
   */
  function register(IBaseWorld world, bytes14 namespace) public {
    // Register the namespace if it doesn't exist yet
    ResourceId tokenNamespace = WorldResourceIdLib.encodeNamespace(namespace);
    if (!ResourceIds.getExists(tokenNamespace)) {
      world.registerNamespace(tokenNamespace);
    }

    // Register the tables
    ERC1155OperatorApproval.register(_operatorApprovalTableId(namespace));
    ERC1155Balances.register(_balancesTableId(namespace));
    ERC1155MetadataURI.register(_metadataURITableId(namespace));

    // Register a new ERC20System
    world.registerSystem(_erc1155SystemId(namespace), new ERC1155System(), true);
  }
}