// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TradingVaultImplementation is Initializable, AccessControlUpgradeable {
    bytes32 private constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    address private _odosRouterAddress;

    error InsufficientBalance;
    error InvalidAmount;
    error TransferFailed;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address odosRouter) public initializer {
        __AccessControl_init();
        _odosRouterAddress = odosRouter;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
    }

    function swap(
        bytes calldata callArgs,
        uint256 amountETH
    ) external onlyRole(OPERATOR_ROLE) returns (uint256) {
        if (address(this).balance < amountETH) {
            revert InsufficientBalance();
        }

        (bool success, bytes memory result) = _odosRouterAddress.call{
            value: msg.value
        }(callArgs);

        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }

        return abi.decode(result, (uint256));
    }

    function withdrawAVAX(
        address to,
        uint256 amount
    ) external onlyRole(OPERATOR_ROLE) {
        uint256 bal = address(this).balance;
        if (amount <= 0) {
            revert InvalidAmount();
        }

        if (bal <= 0 || bal <= amount) {
            revert InsufficientBalance();
        }

        (bool success, ) = to.call{value: amount}("");
        if (!success) {
            revert TransferFailed();
        }
    }

    function withdrawAVAX(address to) external onlyRole(OPERATOR_ROLE) {
        uint256 bal = address(this).balance;
        if (bal <= 0) {
            revert InsufficientBalance();
        }
        (bool success, ) = to.call{value: bal}("");
        if (!success) {
            revert TransferFailed();
        }
    }

    function withdrawERC20(
        address token,
        address to
    ) external onlyRole(OPERATOR_ROLE) {
        IERC20 tokenContract = IERC20(token);
        uint256 bal = tokenContract.balanceOf(address(this));

        if (bal <= 0) {
            revert InsufficientBalance();
        }

        if (!tokenContract.transfer(to, bal)) {
            revert TransferFailed();
        }
    }

    function withdrawERC20(
        address token,
        address to,
        uint256 amount
    ) external onlyRole(OPERATOR_ROLE) {
        IERC20 tokenContract = IERC20(token);
        uint256 bal = tokenContract.balanceOf(address(this));
        if (amount <= 0) {
            revert InvalidAmount();
        }

        if (bal <= 0 || bal < amount) {
            revert InsufficientBalance();
        }

        if (!tokenContract.transfer(to, amount)) {
            revert TransferFailed();
        }
    }

    // Function to receive AVAX
    receive() external payable {}

    // Optional: fallback function for when receive() doesn't match
    fallback() external payable {}
}
