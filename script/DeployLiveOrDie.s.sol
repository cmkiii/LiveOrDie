// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { Script } from "forge-std/Script.sol";
import { LiveOrDie, LiveOrDieRoundTwo } from "../src/LiveOrDie.sol";

contract DeployLiveOrDie is Script {
    function run() external returns (LiveOrDie, LiveOrDieRoundTwo) {
        vm.startBroadcast();

        LiveOrDie liveOrDie = new LiveOrDie(msg.sender);
        LiveOrDieRoundTwo liveOrDieRoundTwo = new LiveOrDieRoundTwo(msg.sender, liveOrDie);

        vm.stopBroadcast();
        return (liveOrDie, liveOrDieRoundTwo);
    }
}
