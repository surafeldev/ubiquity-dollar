// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.19;

import {UbiquityAMOMinter} from "../core/UbiquityAMOMinter.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPool} from "@aavev3-core/contracts/interfaces/IPool.sol";
import {IPoolDataProvider} from "@aavev3-core/contracts/interfaces/IPoolDataProvider.sol";
import {IRewardsController} from "@aavev3-periphery/contracts/rewards/interfaces/IRewardsController.sol";
import {IStakedToken} from "@aavev3-periphery/contracts/rewards/interfaces/IStakedToken.sol";

contract AaveAMO is Ownable {
    using SafeERC20 for ERC20;

    /* ========== STATE VARIABLES ========== */
    address public timelock_address;

    // Constants
    UbiquityAMOMinter private amo_minter;

    // Pools and vaults
    IPool private constant aave_pool =
        IPool(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);

    // Reward Tokens
    ERC20 private constant AAVE =
        ERC20(0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9);

    IRewardsController private constant AAVERewardsController =
        IRewardsController(0x8164Cc65827dcFe994AB23944CBC90e0aa80bFcb);

    IPoolDataProvider private constant AAVEPoolDataProvider =
        IPoolDataProvider(0x7B4EB56E7CD4b454BA8ff71E4518426369a138a3);

    // Borrowed assets
    address[] public aave_borrow_asset_list;
    mapping(address => bool) public aave_borrow_asset_check; // Mapping is also used for faster verification

    /* ========== CONSTRUCTOR ========== */

    constructor(address _owner_address, address _amo_minter_address) {
        // Set owner
        transferOwnership(_owner_address);

        // Set AMO minter
        amo_minter = UbiquityAMOMinter(_amo_minter_address);

        // Get the timelock address from the minter
        timelock_address = amo_minter.timelock_address();
    }

    /* ========== MODIFIERS ========== */

    modifier onlyByOwnGov() {
        require(
            msg.sender == timelock_address || msg.sender == owner(),
            "Not owner or timelock"
        );
        _;
    }

    modifier onlyByMinter() {
        require(msg.sender == address(amo_minter), "Not minter");
        _;
    }

    /* ========== VIEWS ========== */

    function showDebtsByAsset(
        address asset_address
    ) public view returns (uint256[3] memory debts) {
        require(
            aave_borrow_asset_check[asset_address],
            "Asset is not available in borrowed list."
        );
        (
            ,
            uint256 currentStableDebt,
            uint256 currentVariableDebt,
            ,
            ,
            ,
            ,
            ,

        ) = AAVEPoolDataProvider.getUserReserveData(
                asset_address,
                address(this)
            );
        debts[0] = currentStableDebt + currentVariableDebt; // Total debt balance
        ERC20 _asset = ERC20(asset_address);
        debts[1] = _asset.balanceOf(address(this)); // AMO Asset balance
        debts[2] = 0; // Removed aaveToken reference (not applicable without aToken)
    }

    /// @notice Shows AMO claimable rewards
    /// @return rewards    Array of rewards addresses
    /// @return amounts    Array of rewards balance
    function showClaimableRewards()
        external
        view
        returns (address[] memory rewards, uint256[] memory amounts)
    {
        address[] memory allTokens = aave_pool.getReservesList();
        (rewards, amounts) = AAVERewardsController.getAllUserRewards(
            allTokens,
            address(this)
        );
    }

    /// @notice Shows the rewards balance of the AMO
    /// @return rewards     Array of rewards addresses
    /// @return amounts     Array of rewards balance
    function showRewardsBalance()
        external
        view
        returns (address[] memory rewards, uint256[] memory amounts)
    {
        rewards = AAVERewardsController.getRewardsList();
        amounts = new uint256[](rewards.length);

        for (uint256 i = 0; i < rewards.length; i++) {
            amounts[i] = ERC20(rewards[i]).balanceOf(address(this));
        }
    }

    /* ========== AAVE V3 + Rewards ========== */

    /// @notice Function to deposit other assets as collateral to Aave pool
    /// @param collateral_address collateral ERC20 address
    /// @param amount Amount of asset to be deposited
    function aaveDepositCollateral(
        address collateral_address,
        uint256 amount
    ) public onlyByOwnGov {
        ERC20 token = ERC20(collateral_address);
        token.safeApprove(address(aave_pool), amount);
        aave_pool.deposit(collateral_address, amount, address(this), 0);
    }

    /// @notice Function to withdraw other assets as collateral from Aave pool
    /// @param collateral_address collateral ERC20 address
    /// @param aToken_amount Amount of asset to be withdrawn
    function aaveWithdrawCollateral(
        address collateral_address,
        uint256 aToken_amount
    ) public onlyByOwnGov {
        aave_pool.withdraw(collateral_address, aToken_amount, address(this));
    }

    /// @notice Function to borrow other assets from Aave pool
    /// @param asset Borrowing asset ERC20 address
    /// @param borrow_amount Amount of asset to be borrowed
    /// @param interestRateMode The interest rate mode: 1 for Stable, 2 for Variable
    function aaveBorrow(
        address asset,
        uint256 borrow_amount,
        uint256 interestRateMode
    ) public onlyByOwnGov {
        aave_pool.borrow(
            asset,
            borrow_amount,
            interestRateMode,
            0,
            address(this)
        );
        aave_borrow_asset_check[asset] = true;
        aave_borrow_asset_list.push(asset);
    }

    /// @notice Function to repay other assets to Aave pool
    /// @param asset Borrowing asset ERC20 address
    /// @param repay_amount Amount of asset to be repaid
    /// @param interestRateMode The interest rate mode: 1 for Stable, 2 for Variable
    function aaveRepay(
        address asset,
        uint256 repay_amount,
        uint256 interestRateMode
    ) public onlyByOwnGov {
        ERC20 token = ERC20(asset);
        token.safeApprove(address(aave_pool), repay_amount);
        aave_pool.repay(asset, repay_amount, interestRateMode, address(this));
    }

    function claimAllRewards() external {
        address[] memory allTokens = aave_pool.getReservesList();
        AAVERewardsController.claimAllRewards(allTokens, address(this));
    }

    /* ========== RESTRICTED GOVERNANCE FUNCTIONS ========== */

    /// @notice Function to return collateral to the minter
    /// @param collat_amount Amount of collateral to return to the minter
    /// @notice If collat_amount is 0, the function will return all the collateral in the AMO
    function returnCollateralToMinter(
        uint256 collat_amount
    ) public onlyByOwnGov {
        ERC20 collateral_token = amo_minter.collateral_token();

        if (collat_amount == 0) {
            collat_amount = collateral_token.balanceOf(address(this));
        }

        // Approve collateral to UbiquityAMOMinter
        collateral_token.approve(address(amo_minter), collat_amount);

        // Call receiveCollatFromAMO from the UbiquityAMOMinter
        amo_minter.receiveCollatFromAMO(collat_amount);
    }

    function setAMOMinter(address _amo_minter_address) external onlyByOwnGov {
        amo_minter = UbiquityAMOMinter(_amo_minter_address);
        timelock_address = amo_minter.timelock_address();
        require(timelock_address != address(0), "Invalid timelock");
    }

    // Emergency ERC20 recovery function
    function recoverERC20(
        address tokenAddress,
        uint256 tokenAmount
    ) external onlyByOwnGov {
        ERC20(tokenAddress).safeTransfer(msg.sender, tokenAmount);
    }

    // Emergency generic proxy - allows owner to execute arbitrary calls on this contract
    function execute(
        address _to,
        uint256 _value,
        bytes calldata _data
    ) external onlyByOwnGov returns (bool, bytes memory) {
        (bool success, bytes memory result) = _to.call{value: _value}(_data);
        return (success, result);
    }
}
