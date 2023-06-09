//SPDX-License-Identifier:MIT

pragma solidity ^0.8.18;

import {ERC20, ERC20Burnable} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

/*
    @title: DecentralisedStableCoin
    @author: Megabyte
    Collateral: Exogenous (ETH & BTC)
    Minting: Algorethemic
    Relative Stability: Pegged to USD

    This contract is meant to be governed by DSCEngine. This contract is just ERC20 implementation of our stablecoin system.
 */

contract DecentralisedStableCoin is ERC20Burnable, Ownable {
    error DecentralisedStableCoin__MustBeMoreThanZero();
    error DecentralisedStableCoin__BurnAmountExceedTheBalance();
    error DecentralisedStableCoin__NotZeroAddress();

    constructor() ERC20("DecentralisedStableCoin", "DSC") {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DecentralisedStableCoin__MustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert DecentralisedStableCoin__BurnAmountExceedTheBalance();
        }
        super.burn(_amount);
    }

    function mint(
        address _to,
        uint256 _amount
    ) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralisedStableCoin__NotZeroAddress();
        }

        if (_amount <= 0) {
            revert DecentralisedStableCoin__MustBeMoreThanZero();
        }

        _mint(_to, _amount);

        return true;
    }
}
