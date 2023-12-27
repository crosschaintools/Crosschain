// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { UpdateScriptBase } from "./utils/UpdateScriptBase.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { DiamondCutFacet, IDiamondCut } from "app/Facets/DiamondCutFacet.sol";
import { DiamondLoupeFacet, IDiamondLoupe } from "app/Facets/DiamondLoupeFacet.sol";
import { OwnershipFacet } from "app/Facets/OwnershipFacet.sol";
import { WithdrawFacet } from "app/Facets/WithdrawFacet.sol";
import { DexManagerFacet } from "app/Facets/DexManagerFacet.sol";
import { AccessManagerFacet } from "app/Facets/AccessManagerFacet.sol";
import { PeripheryRegistryFacet } from "app/Facets/PeripheryRegistryFacet.sol";

contract DeployScript is UpdateScriptBase {
    using stdJson for string;

    function run() public returns (address[] memory facets) {
        address diamondLoupe = json.readAddress(".DiamondLoupeFacet");
        address ownership = json.readAddress(".OwnershipFacet");
        address withdraw = json.readAddress(".WithdrawFacet");
        address dexMgr = json.readAddress(".DexManagerFacet");
        address accessMgr = json.readAddress(".AccessManagerFacet");
        address peripheryRgs = json.readAddress(".PeripheryRegistryFacet");

        vm.startBroadcast(deployerPrivateKey);

        bytes4[] memory emptyExclude;

        // Diamond Loupe
        cut.push(
            IDiamondCut.FacetCut({
                facetAddress: address(diamondLoupe),
                action: IDiamondCut.FacetCutAction.Add,
                functionSelectors: getSelectors(
                    "DiamondLoupeFacet",
                    emptyExclude
                )
            })
        );

        // Ownership Facet
        cut.push(
            IDiamondCut.FacetCut({
                facetAddress: address(ownership),
                action: IDiamondCut.FacetCutAction.Add,
                functionSelectors: getSelectors("OwnershipFacet", emptyExclude)
            })
        );

        // Withdraw Facet
        cut.push(
            IDiamondCut.FacetCut({
                facetAddress: withdraw,
                action: IDiamondCut.FacetCutAction.Add,
                functionSelectors: getSelectors("WithdrawFacet", emptyExclude)
            })
        );

        // Dex Manager Facet
        cut.push(
            IDiamondCut.FacetCut({
                facetAddress: dexMgr,
                action: IDiamondCut.FacetCutAction.Add,
                functionSelectors: getSelectors(
                    "DexManagerFacet",
                    emptyExclude
                )
            })
        );

        // Access Manager Facet
        cut.push(
            IDiamondCut.FacetCut({
                facetAddress: accessMgr,
                action: IDiamondCut.FacetCutAction.Add,
                functionSelectors: getSelectors(
                    "AccessManagerFacet",
                    emptyExclude
                )
            })
        );

        // PeripheryRegistry
        cut.push(
            IDiamondCut.FacetCut({
                facetAddress: peripheryRgs,
                action: IDiamondCut.FacetCutAction.Add,
                functionSelectors: getSelectors(
                    "PeripheryRegistryFacet",
                    emptyExclude
                )
            })
        );

        cutter.diamondCut(cut, address(0), "");

        facets = loupe.facetAddresses();

        vm.stopBroadcast();
    }
}
