// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { DeployScriptBase } from "./utils/DeployScriptBase.sol";
import { stdJson } from "forge-std/Script.sol";
import { TcrossFacet } from "app/Facets/TcrossFacet.sol";

contract DeployScript is DeployScriptBase {
    using stdJson for string;

    constructor() DeployScriptBase("TcrossFacet") {}

    function run()
        public
        returns (TcrossFacet deployed, bytes memory constructorArgs)
    {
        string memory path = string.concat(
            vm.projectRoot(),
            "/config/tcross.json"
        );
        string memory json = vm.readFile(path);
        address bridge = json.readAddress(
            string.concat(".", network, ".bridge")
        );

        constructorArgs = abi.encode(bridge);

        vm.startBroadcast(deployerPrivateKey);

        if (isDeployed()) {
            return (TcrossFacet(payable(predicted)), constructorArgs);
        }

        deployed = TcrossFacet(
            payable(
                factory.deploy(
                    salt,
                    bytes.concat(
                        type(TcrossFacet).creationCode,
                        constructorArgs
                    )
                )
            )
        );

        vm.stopBroadcast();
    }
}
