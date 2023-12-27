#!/bin/bash

# load env variables
source .env

# check if env variable "PRODUCTION" is true, otherwise deploy as staging
if [[ -z "$PRODUCTION" ]]; then
  FILE_SUFFIX="staging."
fi


# Periphery合约注册功能
registerFeeCollector() {
  ADDRS="deployments/$NETWORK.${FILE_SUFFIX}json"
  DIAMOND=$(jq -r '.Diamond' $ADDRS)
  NAME="FeeCollector"
  FEECOLLECTOR=$(jq -r '.FeeCollector // "0x"' $ADDRS)
  echo "registerPeripheryContract $NAME $FEECOLLECTOR"
  RPC="ETH_NODE_URI_$(tr '[:lower:]' '[:upper:]' <<<$NETWORK)"
  cast send $DIAMOND 'registerPeripheryContract(string,address)' "$NAME" "$FEECOLLECTOR" --private-key $PRIVATE_KEY --rpc-url "${!RPC}" --legacy
}

syncDexs(){
  DIAMOND=$(jq -r '.Diamond' "./deployments/${NETWORK}.${FILE_SUFFIX}json")
  echo "Diamond address: $DIAMOND"
  CFG_DEXS=($(jq --arg n "$NETWORK" -r '.[$n] | @sh' "./config/dexs.json" | tr -d \' | tr '[:upper:]' '[:lower:]'))

  RPC="ETH_NODE_URI_$(tr '[:lower:]' '[:upper:]' <<< "$NETWORK")"

  RESULT=$(cast call "$DIAMOND" "approvedDexs() returns (address[])" --rpc-url "${!RPC}")
  DEXS=($(echo ${RESULT:1:${#RESULT}-1} | tr ',' '\n' | tr '[:upper:]' '[:lower:]'))

  NEW_DEXS=()
  for dex in "${CFG_DEXS[@]}"; do
    if [[ ! " ${DEXS[*]} " =~ " ${dex} " ]]; then
      NEW_DEXS+=($dex)
    fi
  done

  if [[ ! ${#NEW_DEXS[@]} -eq 0 ]]; then
    echo 'Adding missing DEXs'
    for d in "${NEW_DEXS[@]}"; do
      DEX_PARAMS+="${d},"
    done

    # execute script
    attempts=1 # initialize attempts to 0
    while [ $attempts -lt 11 ]; do
      echo "Trying to execute batchAddDex now - attempt ${attempts}"
      # try to execute call
      RAW_RETURN_DATA=$(cast send $DIAMOND "batchAddDex(address[])" "[${DEX_PARAMS::${#DEX_PARAMS}-1}]" --rpc-url ${!RPC} --private-key ${PRIVATE_KEY} --legacy)
      echo "RAW_RETURN_DATA：" $RAW_RETURN_DATA
      # check the return code the last call
      if [ -n "${RAW_RETURN_DATA}" ]; then
        break # exit the loop if the operation was successful
      fi

      attempts=$((attempts + 1)) # increment attempts
      sleep 1                    # wait for 1 second before trying the operation again
    done
    #cast send $DIAMOND "batchAddDex(address[])" "[${DEX_PARAMS::${#DEX_PARAMS}-1}]" --rpc-url ${!RPC} --private-key ${PRIVATE_KEY} --legacy
  else
    echo 'No new DEXs to add'
  fi
}

syncSigs(){
  DIAMOND=$(jq -r '.Diamond' "./deployments/${NETWORK}.${FILE_SUFFIX}json")
  CFG_SIGS=($(jq -r '.[] | @sh' "./config/sigs.json" | tr -d \' | tr '[:upper:]' '[:lower:]' ))

  RPC="ETH_NODE_URI_$(tr '[:lower:]' '[:upper:]' <<< "$NETWORK")"

  echo 'Updating Sigs'
  for d in "${CFG_SIGS[@]}"; do
    SIG_PARAMS+="${d},"
  done

  # execute script
  attempts=1 # initialize attempts to 0
  while [ $attempts -lt 21 ]; do
    echo "Trying to execute batchSetFunctionApprovalBySignature now - attempt ${attempts}"
    # try to execute call
	  RAW_RETURN_DATA=$(cast send $DIAMOND "batchSetFunctionApprovalBySignature(bytes4[],bool)" "[${SIG_PARAMS::${#SIG_PARAMS}-1}]" true --rpc-url ${!RPC} --private-key ${PRIVATE_KEY} --legacy)
    echo "RAW_RETURN_DATA：" $RAW_RETURN_DATA
    # check the return code the last call
    if [ -n "${RAW_RETURN_DATA}" ]; then
      break # exit the loop if the operation was successful
    fi

    attempts=$((attempts + 1)) # increment attempts
    sleep 1                    # wait for 1 second before trying the operation again
  done

  #cast send $DIAMOND "batchSetFunctionApprovalBySignature(bytes4[],bool)" "[${SIG_PARAMS::${#SIG_PARAMS}-1}]" true --rpc-url ${!RPC} --private-key ${PRIVATE_KEY} --legacy
}

update() {
  CONTRACT=$1
  SCRIPT=Update$CONTRACT

  echo $(date) "Updating $SCRIPT on $NETWORK"
  USE_DEF_DIAMOND=true

  # execute script
  attempts=1 # initialize attempts to 0

  while [ $attempts -lt 21 ]; do
    echo $(date) "Trying to execute $SCRIPT now - attempt ${attempts}"
    # try to execute call
	  RAW_RETURN_DATA=$(NETWORK=$NETWORK FILE_SUFFIX=$FILE_SUFFIX USE_DEF_DIAMOND=$USE_DEF_DIAMOND forge script script/$SCRIPT.s.sol -f $NETWORK -vvvvv --json --silent --broadcast --verify --skip-simulation --legacy)

    # check the return code the last call
    if [ $? -eq 0 ]; then
      break # exit the loop if the operation was successful
    fi

    attempts=$((attempts + 1)) # increment attempts
    sleep 1                    # wait for 1 second before trying the operation again
  done

  if [ $attempts -eq 21 ]; then
    echo "Failed to execute $SCRIPT"
    exit 1
  fi

  echo "RAW_RETURN_DATA：" $RAW_RETURN_DATA
  # extract the "logs" property and its contents from return data
	CLEAN_RETURN_DATA=$(echo $RAW_RETURN_DATA | sed 's/^.*{\"logs/{\"logs/')
  # extract the "returns" property and its contents from logs
	RETURN_DATA=$(echo $CLEAN_RETURN_DATA | jq -r '.returns' 2> /dev/null)
  #echo $RETURN_DATA
	echo $CLEAN_RETURN_DATA | jq 2> /dev/null

	facets=$(echo $RETURN_DATA | jq -r '.facets.value')

	saveDiamond $USE_DEF_DIAMOND "$facets"

  echo "$SCRIPT successfully executed on network $NETWORK"
}

saveDiamond() {
  # store function arguments in variables
	USE_DEF_DIAMOND=$1
	FACETS=$(echo $2 | tr -d '[' | tr -d ']' | tr -d ',')
	FACETS=$(printf '"%s",' $FACETS | sed 's/,*$//')

  # define path for json file based on which diamond was used
  if [[ "$USE_DEF_DIAMOND" == "true" ]]; then
    DIAMOND_FILE="./deployments/${NETWORK}.diamond.${FILE_SUFFIX}json"
  else
    DIAMOND_FILE="./deployments/${NETWORK}.diamond.immutable.${FILE_SUFFIX}json"
  fi

	# create an empty json if it does not exist
	if [[ ! -e $DIAMOND_FILE ]]; then
		echo "{}" >"$DIAMOND_FILE"
	fi
	result=$(cat "$DIAMOND_FILE" | jq -r ". + {\"facets\": [$FACETS] }" || cat "$DIAMOND_FILE")
	printf %s "$result" >"$DIAMOND_FILE"
}


# 部署指定合约
deploy() {
  CONTRACT=$1
  SCRIPT=Deploy$CONTRACT
  echo $(date) "deploy ${CONTRACT}, script: ${SCRIPT}"

  # if selected contract is "DiamondImmutable" then use an adjusted salt for deployment to prevent clashes
  if [[ $CONTRACT = "DiamondImmutable" ]]; then
    # adjust contract name (remove "Immutable") since we are using our standard diamond contract
    CONTRACTADJ=$(echo "$CONTRACT"V1) # << this needs to be updated when releasing a new version
    # get contract bytecode
    BYTECODE=$(forge inspect $CONTRACTADJ bytecode)
    # adds a string to the end of the bytecode to alter the salt but always produce deterministic results based on bytecode
    BYTECODEADJ="$BYTECODE"ffffffffffffffffffffffffffffffffffffff$DEPLOYSALT
    # create salt with keccak(bytecode)
    DEPLOYSALT=$(cast keccak $BYTECODEADJ)
  else
    # in all other cases just create a salt just based on the contract bytecode
    CONTRACTADJ=$CONTRACT
    BYTECODE=$(forge inspect $CONTRACT bytecode)
    DEPLOYSALT=$(cast keccak $BYTECODE)
  fi

  # execute script
  attempts=1 # initialize attempts to 0

  while [ $attempts -lt 21 ]; do
    echo "Trying to deploy $CONTRACTADJ now - attempt ${attempts}"
    # try to execute call
    RAW_RETURN_DATA=$(DEPLOYSALT=$DEPLOYSALT NETWORK=$NETWORK FILE_SUFFIX=$FILE_SUFFIX forge script script/$SCRIPT.s.sol -f $NETWORK -vvvvv --json --silent --broadcast --skip-simulation --legacy)

    # check the return code the last call
    if [ $? -eq 0 ]; then
      break # exit the loop if the operation was successful
    fi

    attempts=$((attempts + 1)) # increment attempts
    sleep 1                    # wait for 1 second before trying the operation again
  done

  if [ $attempts -eq 21 ]; then
    echo "Failed to deploy $CONTRACTADJ"
    exit 1
  fi
  echo $RAW_RETURN_DATA
  # clean tx return data
  CLEAN_RETURN_DATA=$(echo $RAW_RETURN_DATA | sed 's/^.*{\"logs/{\"logs/')
  echo $CLEAN__RETURN_DATA | jq 2>/dev/null
  checkFailure

  # extract the "returns" field and its contents from the return data (+hide errors)
  RETURN_DATA=$(echo $CLEAN_RETURN_DATA | jq -r '.returns' 2>/dev/null)

  # extract deployed-to address from return data
  deployed=$(echo $RETURN_DATA | jq -r '.deployed.value')
  # extract constructor arguments from return data
  args=$(echo $RETURN_DATA | jq -r '.constructorArgs.value // "0x"')
  echo "$CONTRACT deployed on $NETWORK at address $deployed"

  saveContract $CONTRACTADJ $deployed
  #verifyContract $CONTRACTADJ $deployed $args
}

saveContract() {
  CONTRACT=$1
  ADDRESS=$2

  ADDRESSES_FILE="./deployments/${NETWORK}.${FILE_SUFFIX}json"

  # create an empty json if it does not exist
  if [[ ! -e $ADDRESSES_FILE ]]; then
    echo "{}" >"$ADDRESSES_FILE"
  fi
  result=$(cat "$ADDRESSES_FILE" | jq -r ". + {\"$CONTRACT\": \"$ADDRESS\"}" || cat "$ADDRESSES_FILE")
  printf %s "$result" >"$ADDRESSES_FILE"
}

verifyContract() {
  CONTRACT=$1
  ADDRESS=$2
  echo "ADDRESS in verify: $ADDRESS"
  ARGS=$4
  API_KEY="$(tr '[:lower:]' '[:upper:]' <<<$NETWORK)_ETHERSCAN_API_KEY"
  if [ "$ARGS" = "0x" ]; then
    forge verify-contract --watch --chain $NETWORK $ADDRESS $CONTRACT "${!API_KEY}"
  else
    forge verify-contract --watch --chain $NETWORK $ADDRESS $CONTRACT --constructor-args $ARGS "${!API_KEY}"
  fi
}

checkFailure() {
  if [[ $? -ne 0 ]]; then
    echo "Failed to deploy $CONTRACT"
    exit 1
  fi
}

