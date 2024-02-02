// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC1155/IERC1155.sol)
pragma solidity >=0.8.24;

import { IERC1155 } from "./IERC1155.sol";

/**
 * @dev Extending the ERC1155 standard with permissioned mint and burn functions.
 */
interface IERC1155Mintable is IERC1155 {
  /**
   * @dev Mints `id` and transfers it to `to`.
   *
   * Requirements:
   *
   * - `tokenId` must not exist.
   * - `to` cannot be the zero address.
   *
   * Emits a {Transfer} event.
   */
  function mint(address to, uint256 id, uint256 value, bytes memory data) external;

  /**
   * @dev Mints `ids` and transfers it to `to`.
   *
   * Requirements:
   *
   * - `tokenId` must not exist.
   * - `to` cannot be the zero address.
   *
   * Emits a {Transfer} event.
   */
  function mintBatch(address to, uint256[] memory ids, uint256[] memory values, bytes memory data) external;

  /**
   * @dev Destroys `id`.
   * The approval is cleared when the token is burned.
   *
   * Requirements:
   *
   * - `id` must exist.
   *
   * Emits a {TransferSingle} event.
   */
  function burn(address account, uint256 id, uint256 value) external;

  /**
   * @dev Destroys `ids`.
   * The approval is cleared when the token is burned.
   *
   * Requirements:
   *
   * - `ids` must exist.
   *
   * Emits a {TransferBatch} event.
   */
  function burnBatch(address account, uint256[] memory ids, uint256[] memory values) external;
}
