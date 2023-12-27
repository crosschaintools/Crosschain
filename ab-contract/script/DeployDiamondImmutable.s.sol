// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { DeployScriptBase } from "./utils/DeployScriptBase.sol";
import { stdJson } from "forge-std/Script.sol";
import { DiamondImmutableV1 } from "app/DiamondImmutable.sol";
import { DiamondCutFacet, IDiamondCut } from "app/Facets/DiamondCutFacet.sol";


contract DeployScript is DeployScriptBase {
    using stdJson for string;

    IDiamondCut.FacetCut[] internal cut;
    address internal diamondImmutable;
    DiamondCutFacet internal cutter;

    constructor() DeployScriptBase("DiamondImmutableV1") {

        network = vm.envString("NETWORK");
        fileSuffix = vm.envString("FILE_SUFFIX");

        string memory path = string.concat(
            root,
            "/deployments/",
            network,
            ".",
            fileSuffix,
            "json"
        );
        string memory json = vm.readFile(path);
        diamondImmutable = json.readAddress(".DiamondImmutableV1");
        cutter = DiamondCutFacet(diamondImmutable);
    }

    function run()
        public
        returns (DiamondImmutableV1 deployed, bytes memory constructorArgs)
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
            return (DiamondImmutableV1(payable(predicted)), constructorArgs);
        }

        deployed = DiamondImmutableV1(
            payable(
                factory.deploy(
                    salt,
                    bytes.concat(
                        type(DiamondImmutableV1).creationCode,
                        constructorArgs
                    )
                )
            )
        );

        vm.stopBroadcast();
    }
}
