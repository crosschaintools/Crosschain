// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { DeployScriptBase } from "./utils/DeployScriptBase.sol";
import { Tcross } from "app/Bridges/Tcross.sol";

contract DeployScript is DeployScriptBase {
    constructor() DeployScriptBase("Tcross") {}

    function run()
        public
        returns (Tcross deployed)
    {
        vm.startBroadcast(deployerPrivateKey);

        if (isDeployed()) {
            return Tcross(predicted);
        }

        deployed = Tcross(
            factory.deploy(
                salt,
                type(Tcross).creationCode
            )
        );

        vm.stopBroadcast();
    }
}
