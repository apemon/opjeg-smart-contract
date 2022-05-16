# OPJEG contract

     Flow 1: mint put (exercised)
     1. mintPut(): writer deposit ETH, set strikePrice < marketPrice
       - Option writer gets OptionNFT
       - Option writer sells OptionNFT in marketplace
     2. exercisePut() by option holder
       - Option holder sends NFT to contract
       - ETH released to option holder
       - OptionNFT burned by contract
     3. claimNFT() by option writer

     Flow 2: mint call (exercised)
     1. mintCall(): writer deposit NFT, set strikePrice > marketPrice
       - Option writer gets OptionNFT
     2. exerciseCall() by option holder
       - Option holder sends _strikePrice ETH to contract
       - NFT released to option holder
       - OptionNFT burned by contract
     3. claimETH() by option writer

     Flow 3: option not exercised
     1. burnOption(): called by anyone, returns ETH or NFT to option writer

     Flow 4: dev claim protocol fee
     1. claim()