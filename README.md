This is new repository to store the test sample of the solidity.

Current they are able to be verified the same assertion of CVL but with solc smt solver. But now the ESBMC cannot.

Besides that Here needs to update current limitation:
1. need to manual check the corresponding result from certora.
2. the certora result is from the contract level, but my result is more like function level. Sometime, LLM generated default ERC-20 transfer withdrawal function is not safe. But the contract might already has some protection on other function.
3. which means the result is not same.







TODO:
1.verify if they are verifying the same property as certora did and what is the difference between result.

2.Find out how to make the workflow works for ESBMC?: adjust the BMC test framework or ask ESBMC to adjust for Solidity 0.8 json?


