# To load the variables in the .env file
source .env
# fix fork-block-number will run faster
forge test --fork-url $ETH_RPC_URL --fork-block-number 17148972 --match-contract UsdcUpgradeTest -vvvvv