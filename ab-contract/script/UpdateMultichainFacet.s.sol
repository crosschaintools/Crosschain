// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { UpdateScriptBase } from "./utils/UpdateScriptBase.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { DiamondCutFacet, IDiamondCut } from "app/Facets/DiamondCutFacet.sol";
import { MultichainFacet } from "app/Facets/MultichainFacet.sol";

contract DeployScript is UpdateScriptBase {
    using stdJson for string;

    function run() public returns (address[] memory facets) {
        address facet = json.readAddress(".MultichainFacet");

        path = string.concat(root, "/config/multichain.json");
        json = vm.readFile(path);
        address[] memory routers = json.readAddressArray(
            string.concat(".", network, ".routers")
        );
        address anyNative = json.readAddress(
            string.concat(".", network, ".anyNative")
        );
        // get anyTokenMappings from config and parse into array
        bytes memory rawConfig = json.parseRaw(
            string.concat(".", network, ".tokens")
        );
        // parse raw data from config into anyMappings array
        MultichainFacet.AnyMapping[] memory addressMappings = abi.decode(
            rawConfig,
            (MultichainFacet.AnyMapping[])
        );

        bytes memory callData = abi.encodeWithSelector(
            MultichainFacet.initMultichain.selector,
            anyNative,
            routers
        );

        vm.startBroadcast(deployerPrivateKey);

        // Multichain
        if (loupe.facetFunctionSelectors(facet).length == 0) {
            bytes4[] memory exclude = new bytes4[](1);
            exclude[0] = MultichainFacet.initMultichain.selector;
            cut.push(
                IDiamondCut.FacetCut({
                    facetAddress: address(facet),
                    action: IDiamondCut.FacetCutAction.Add,
                    functionSelectors: getSelectors("MultichainFacet", exclude)
                })
            );
            cutter.diamondCut(cut, address(facet), callData);
        }

        facets = loupe.facetAddresses();
        MultichainFacet(diamond).updateAddressMappings(addressMappings);

        vm.stopBroadcast();
    }
}
