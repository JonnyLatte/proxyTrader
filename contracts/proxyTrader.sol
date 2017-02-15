pragma solidity ^0.4.6;

// https://github.com/ethereum/EIPs/issues/20
contract ERC20 {
    function totalSupply() constant returns (uint totalSupply);
    function balanceOf(address _owner) constant returns (uint balance);
    function transfer(address _to, uint _value) returns (bool success);
    function transferFrom(address _from, address _to, uint _value) returns (bool success);
    function approve(address _spender, uint _value) returns (bool success);
    function allowance(address _owner, address _spender) constant returns (uint remaining);
    event Transfer(address indexed _from, address indexed _to, uint _value);
    event Approval(address indexed _owner, address indexed _spender, uint _value);
}

contract proxyRecipient {
    function proxyTransfer(address caller) payable returns (bool ok);
}

contract proxyAddress {
    
    proxyRecipient owner;
    
    function proxyAddress() 
    {
       owner = proxyRecipient(msg.sender);
    }

    function() payable {
        if(!owner.proxyTransfer.value(msg.value)(msg.sender)) throw;
    }
}

contract proxyTrader is proxyRecipient {
    
    struct OFFER_DATA 
    {
        address maker;
        ERC20   asset;
        uint256 maker_sell_asset_units;
        uint256 maker_sell_ether_price;
        uint256 maker_buy_asset_units;
        uint256 maker_buy_ether_price;
        bool    buys;
        bool    sells;
        proxyAddress proxy;
    }
    
    mapping(uint256 => uint256) public maker_ether_balance;
    mapping(uint256 => uint256) public maker_asset_balance;
    
    mapping(address => uint256) public proxyid;

    uint256 public last_offer_id;
    mapping(uint256 => OFFER_DATA) offer_data;
    
    event tradeListingEvent(
        address indexed maker, 
        uint256 id,
        address indexed asset, 
        uint256 maker_sell_asset_units,
        uint256 maker_sell_ether_price,
        uint256 maker_buy_asset_units,
        uint256 maker_buy_ether_price,
        bool    buys,
        bool    sells,
        address indexed ethProxy);
        
    event takerBuysAssetEvent(
        uint256 indexed id, 
        address indexed maker,
        address taker,
        address indexed asset, 
        uint256 etherValueOfTrade, 
        uint256 assetValueOfTrade);
        
    event takerSellsAssetEvent(
        uint256 indexed id, 
        address indexed maker,
        address taker,
        address indexed asset, 
        uint256 etherValueOfTrade, 
        uint256 assetValueOfTrade);
        
    event makerActivateOfferEvent(
        uint256 indexed id, 
        bool buys, 
        bool sells);

    function next_offer_id() internal returns(uint256) {
        return ++last_offer_id;
    }
    
    function offerDetails(uint256 id) constant returns (
        address    maker,
        address    asset,
        uint256    maker_sell_asset_units,
        uint256    maker_sell_ether_price,
        uint256    maker_buy_asset_units,
        uint256    maker_buy_ether_price,
        bool    buys,
        bool    sells,
        address etherProxy,
        uint256 ethBalance,
        uint256 assetBalance
    ) {
        var offer = offer_data[id];    
        
        maker = offer.maker;
        asset = offer.asset;
        maker_sell_asset_units = offer.maker_sell_asset_units;
        maker_sell_ether_price = offer.maker_sell_ether_price;
        maker_buy_asset_units = offer.maker_buy_asset_units;
        maker_buy_ether_price = offer.maker_buy_ether_price;
        buys = offer.buys;
        sells = offer.sells;
        etherProxy = offer.proxy;
        ethBalance = maker_ether_balance[id];
        assetBalance = maker_asset_balance[id];
    }
    
    function createOffer (
        ERC20 asset,
        uint256 maker_sell_asset_units,
        uint256 maker_sell_ether_price,
        uint256 maker_buy_asset_units,
        uint256 maker_buy_ether_price,
        bool buys,
        bool sells,
        uint256 initialAssetDepositSmallestUnits
        ) payable
    {
        var id = next_offer_id();
        
        proxyAddress proxy = new proxyAddress();

        offer_data[id] = OFFER_DATA(
            msg.sender,
            asset,
            maker_sell_asset_units,
            maker_sell_ether_price,
            maker_buy_asset_units,
            maker_buy_ether_price,
            buys,
            sells,
            proxy);
            
        proxyid[proxy] = id;
        
        tradeListingEvent(
            msg.sender,
            id,
            asset,
            maker_sell_asset_units,
            maker_sell_ether_price,
            maker_buy_asset_units,
            maker_buy_ether_price,
            buys,
            sells,
            proxy);
            
        if(initialAssetDepositSmallestUnits > 0) makerDepositAsset(id, initialAssetDepositSmallestUnits);
        if(msg.value > 0) maker_ether_balance[id] = msg.value;
    }

    function makerDepositAsset(uint256 id, uint256 assetValueSmallestUnits) 
    {
        var offer = offer_data[id];
        if(offer.maker != msg.sender) throw;
        if(!offer.asset.transferFrom(msg.sender,this,assetValueSmallestUnits)) throw;
        
        // credit assets from maker, to prevent recursive attacks (built into a token?)
        // this must happen after external call "transferFrom"
        if(maker_asset_balance[id] + assetValueSmallestUnits < assetValueSmallestUnits) throw; // overflow check
        maker_asset_balance[id] = maker_asset_balance[id] + assetValueSmallestUnits;
    }
    
    function makerWithdrawAsset(uint256 id, uint256 assetValueSmallestUnits) 
    {
        var offer = offer_data[id];
        if(offer.maker != msg.sender) throw;
        
        // clamp withdrawal to available funds
        if(maker_asset_balance[id] < assetValueSmallestUnits) {
            assetValueSmallestUnits = maker_asset_balance[id];    
        }
        
        // remove assets from maker, to prevent recursive attacks (built into a token?)
        // this must happen before external call "transfer"
        maker_asset_balance[id] = maker_asset_balance[id] - assetValueSmallestUnits;
        if(!offer.asset.transfer(msg.sender,assetValueSmallestUnits)) throw;
    }
    
    function makerTransferEther(uint256 id_from, uint256 id_to, uint256 etherValue) 
    {
        if(offer_data[id_from].maker != msg.sender) throw; // must own both offers
        if(offer_data[id_to].maker != msg.sender) throw;
        
        if(maker_ether_balance[id_from] < etherValue)  throw; // must have the funds
        maker_ether_balance[id_from] = maker_ether_balance[id_from] - etherValue;
        
        if(maker_ether_balance[id_to] + etherValue < etherValue) throw; // overflow check
        maker_ether_balance[id_to] = maker_ether_balance[id_to] + etherValue;
    }
    
    function makerTransferAsset(uint256 id_from, uint256 id_to, uint256 assetValue) 
    {
        if(offer_data[id_from].maker != msg.sender) throw; // must own both offers
        if(offer_data[id_to].maker != msg.sender) throw;
        if(offer_data[id_from].asset != offer_data[id_to].asset) throw; // must be offering same asset
        
        var asset = offer_data[id_from].asset;
        
        if(maker_asset_balance[id_from] < assetValue)  throw; // must have the funds
        maker_asset_balance[id_from] = maker_asset_balance[id_from] - assetValue;
        
        if(maker_asset_balance[id_to] + assetValue < assetValue) throw; // overflow check
        maker_asset_balance[id_to] = maker_asset_balance[id_to] + assetValue;
    }
    
    function makerWithdrawEther(uint256 id, uint256 etherValueSmallestUnits) {
        if(offer_data[id].maker != msg.sender) throw; // must own offer
        if(maker_ether_balance[id] < etherValueSmallestUnits)  throw; // must have the funds
        maker_ether_balance[id] = maker_ether_balance[id] - etherValueSmallestUnits; // remove funds
        if(!msg.sender.send(etherValueSmallestUnits)) throw; // send make their ether
    }
    
    function makerWithdrawAndDeactivate(uint id) {
        makerWithdrawEther(id,maker_ether_balance[id]);
        makerWithdrawAsset(id,maker_asset_balance[id]);
        makerActivateOffer(id, false, false);
    }
    
    function makerDepositEther(uint256 id) payable {
        var offer = offer_data[id];
        if(offer.maker != msg.sender) throw;
        
        if(maker_ether_balance[id] + msg.value < msg.value) throw; // overflow check
        maker_ether_balance[id] = maker_ether_balance[id] + msg.value;
    }
    
    function makerFundAndActivate(uint id, bool buys, bool sells, uint256 assetValueSmallestUnits) payable {
        makerActivateOffer(id, buys, sells); // throws if sender is not maker for this id
        makerDepositEther(id);
        makerDepositAsset(id, assetValueSmallestUnits);
    }

    function makerActivateOffer(uint256 id, bool buys, bool sells) {
        
        if(offer_data[id].maker != msg.sender) throw;
        
        offer_data[id].buys  = buys;
        offer_data[id].sells = sells;
        
        makerActivateOfferEvent(id,buys,sells);
    }
    
    function takerBuysAsset(uint256 id) payable 
    {
        takerBuysAssetImplementation(id,msg.sender, msg.value);
    }
    
    function takerSellsAsset(uint256 id, uint256 assetValueSmallestUnits) 
    {
        takerSellsAssetImplementation(id,msg.sender, assetValueSmallestUnits);
    }
    
    function proxyTransfer(address caller) payable returns (bool ok) {
        takerBuysAssetImplementation(proxyid[msg.sender],caller, msg.value);
        return true;
    }
    
    function takerBuysAssetImplementation(
        uint256 id,
        address taker, 
        uint256 etherValueSent
        ) internal 
    {
        var offer = offer_data[id];
        
        if(offer.maker == 0) throw;     // must be valid offer
        if(offer.sells == false) throw; // must be selling
        
        var unitLots           = etherValueSent / offer.maker_sell_ether_price;
        var makerAssetBalance  = maker_asset_balance[id];

        // clamp trade value to the value of the assets being sold
        if(unitLots > makerAssetBalance / offer.maker_sell_asset_units) {
            unitLots = makerAssetBalance / offer.maker_sell_asset_units;
        }
        
        var etherValueOfTrade = unitLots * offer.maker_sell_ether_price;
        var assetValueOfTrade = unitLots * offer.maker_sell_asset_units;
        
        if(etherValueOfTrade < unitLots) throw; // overflow check
        if(assetValueOfTrade < unitLots) throw; // overflow check
        
        if(etherValueOfTrade < etherValueSent) {
            if(!taker.send(etherValueSent - etherValueOfTrade)) throw; // refund ether change
        }
        
        maker_ether_balance[id] = maker_ether_balance[id] + etherValueOfTrade; // credit maker the either
        
        maker_asset_balance[id] = makerAssetBalance - assetValueOfTrade; // subtract tokens from maker
        if(!offer.asset.transfer(taker,assetValueOfTrade)) throw; // send taker their tokens
        
        takerBuysAssetEvent(
            id, 
            offer.maker,
            taker,
            offer.asset, 
            etherValueOfTrade, 
            assetValueOfTrade);
    }
    
    function takerSellsAssetImplementation(
        uint256 id,
        address taker, 
        uint256 assetValueOffered
        ) internal 
    {
        var offer = offer_data[id];
        
        if(offer.maker == 0) throw;     // must be valid offer
        if(offer.buys == false) throw; // must be selling
        
        var unitLots = assetValueOffered / offer.maker_buy_asset_units; 
        var makerEtherBalance = maker_ether_balance[id];
        
        // clamp trade to available ether
        if(unitLots > makerEtherBalance / offer.maker_buy_ether_price) {
            unitLots = makerEtherBalance / offer.maker_buy_ether_price;
        }
        
        // no need to check overflow on assetValueOfTrade as 
        // unitLots * offer.maker_buy_asset_units no greater than assetValueOffered
        var assetValueOfTrade = unitLots * offer.maker_buy_asset_units; 
        
        if(unitLots * offer.maker_buy_ether_price < unitLots) throw; // overflow check;
        var etherValueOfTrade = unitLots * offer.maker_buy_ether_price;   
        
        if(!offer.asset.transferFrom(taker,this,assetValueOfTrade)) throw; // transfer user assets
    
        if(maker_asset_balance[id] + assetValueOfTrade < assetValueOfTrade) throw; //overflow check
        maker_asset_balance[id] = maker_asset_balance[id] + assetValueOfTrade;     // credit maker assets

        
        // unitLots previously clamped to makerEtherBalance / offer.maker_buy_ether_price (no overflow check needed)
        maker_ether_balance[id] = makerEtherBalance - etherValueOfTrade; // remove maker ether
         
        if(!taker.send(etherValueOfTrade)) throw; // ende taker their either
        
        takerSellsAssetEvent(
            id, 
            offer.maker,
            taker,
            offer.asset, 
            etherValueOfTrade, 
            assetValueOfTrade);
    }
    
    function () {
        throw;  // no sending ether to proxyTrader
    }
}