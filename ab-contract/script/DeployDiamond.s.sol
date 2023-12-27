// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { DeployScriptBase } from "./utils/DeployScriptBase.sol";
import { stdJson } from "forge-std/Script.sol";
import { Diamond } from "app/Diamond.sol";

contract DeployScript is DeployScriptBase {
    using stdJson for string;

    constructor() DeployScriptBase("Diamond") {}

    function run()
        public
        returns (Diamond deployed, bytes memory constructorArgs)
    {
        string memory path = string.concat(
            root,
            "/deployments/",
            network,
            ".",
            fileSuffix,
            "json"
        );
        string memory json = vm.readFile(path);
        address diamondCut = json.readAddress(".DiamondCutFacet");

        constructorArgs = abi.encode(deployerAddress, diamondCut);

        vm.startBroadcast(deployerPrivateKey);

        if (isDeployed()) {
            return (Diamond(payable(predicted)), constructorArgs);
        }

        deployed = Diamond(
            payable(
                factory.deploy(
                    salt,
                    bytes.concat(
                        type(Diamond).creationCode,
                        constructorArgs
                    )
                )
            )
        );

        vm.stopBroadcast();
    }
}
