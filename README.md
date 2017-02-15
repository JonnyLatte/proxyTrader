# portrayed

Ethereum ETH / ERC20 OTC exchange

This platform is in development.  

Allows users to create an offer to buy and or sell ERC20 tokens for Ether.

The contract holds funds for multiple users (associated with offers they own) as such special care needs to be taken during security audits to ensure users can only claim their own funds. 

A special feature of this exchange is the ability to execute a buy by just sending ether to an address (created when an offer is created).

Offers can also repeatedly buy and sell without maker interaction. 

Creating an offer allows for its funding of both the Token and or Ether potentially saving 2 extra transactions. 

Funds can be transferred from one offer to another by their owner.

#It is unwise to use this contract outside of tested until it has undergone thorough security auditing, especially considering it is currently being designed. 
