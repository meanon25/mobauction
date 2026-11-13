-- Auction access follows the visible game window required by Auctionator.
return function(F,eq,fire,widget)
  for _,key in ipairs({'window','setup','report','details','settings'}) do
    if F[key] then F[key].suppressReturn=true; F[key]:Hide(); F[key].suppressReturn=nil end
  end
  TradeSkillFrame=nil; CraftFrame=nil; ProfessionsFrame=nil
  F.recipeSourceOpen=false; F.recipeSourceChanging=false; F.filter=185; F.worthLearning=false
  C_SkillInfo=nil
  GetProfessions=function() return 1 end
  GetProfessionInfo=function() return 'Cooking',nil,244,300,nil,nil,185 end
  MobAuctionDB={scanForecastsEnabled=true,strictCosts=true,assumedDeposit=false,setupComplete=true,selectedProfessions={[185]=true},detectedSkills={[185]=244},
    recipes={[2538]={id=2538,name='Known Cooking item',profession=185,learned=true,professionVerified=true,
      observedBuild=F.Build(),observedSkill=244,output=100,made=1,reagents={{itemID=200,qty=3}}}}}
  F.Init(); F.DiscoverProfessions()
  F.depth={}; F.depthRequests={}; F.deals={}; F.priceCache={}; F.ahOpen=false
  F.db.dealAlerts=false
  local say=F.Say; local messages={}
  F.Say=function(message) messages[#messages+1]=message end
  C_Item={GetItemInfo=function(id)
    return 'AH item '..id,nil,nil,nil,nil,nil,nil,nil,nil,nil,9,id==900 and 9 or 7,id==900 and 5 or 0,0
  end}
  local searches,requests,depositQueries=0,0,0
  local terms,lastRequest
  Auctionator={API={v1={
    GetAuctionPriceByItemID=function() return 100 end,
    GetAuctionAgeByItemID=function() return 0 end,
    MultiSearchExact=function(_,items) searches=searches+1; terms=items end,
  }}}
  AHledgerAPI={GetPrice=function() return {median7d=10000,updated=time()} end}
  local unitPrice=20
  C_AuctionHouse={
    MakeItemKey=function(id) return {itemID=id,itemLevel=0,itemSuffix=0,battlePetSpeciesID=0} end,
    GetItemKeyInfo=function() return {isCommodity=true} end,
    CalculateCommodityDeposit=function(_,_,quantity) depositQueries=depositQueries+1; return quantity*2 end,
    IsThrottledMessageSystemReady=function() return true end,
    SendSearchQuery=function(key) requests=requests+1; lastRequest=key.itemID end,
    HasFullCommoditySearchResults=function() return true end,
    GetNumCommoditySearchResults=function() return 1 end,
    GetCommoditySearchResultInfo=function() return {unitPrice=unitPrice,quantity=100} end,
    GetBrowseResults=function() return {{itemKey={itemID=900},minPrice=5000}} end,
  }
  Enum.PlayerInteractionType={Auctioneer=21,Merchant=5}
  local providers,candidates,sources,level=F.FarmProviders,F.FarmCandidates,F.FarmSources,F.FarmLevel
  F.FarmProviders=function() return {} end
  F.FarmCandidates=function() return {200} end
  F.FarmSources=function() return {{level=1}} end
  F.FarmLevel=function() return 60 end

  -- The reported failure: no SHOW event was received, but the real AH is open.
  AuctionHouseFrame=widget(); AuctionFrame=nil
  eq(F.IsAuctionHouseOpen(),true,'visible modern auction frame repairs a missed SHOW event')
  eq(searches,0,'discovering an open frame does not start a scan')
  F.ahOpen=false; F.ScanCraftPrices()
  eq(searches,1,'Scan starts Auctionator despite an old false event flag')
  eq(#terms,2,'craft scan includes the learned output and reagent')
  local searched={}; for _,term in ipairs(terms) do searched[term]=true end
  eq(searched['AH item 100'] and searched['AH item 200'],true,'craft scan sends the actual imported item names')
  F.ahOpen=false
  eq(F.Deposit(100,2,1),4,'visible AH permits a game deposit quote despite false cache')
  eq(depositQueries,1,'deposit gate reaches the game API')
  F.ahOpen=false; F.RequestDepth(200)
  eq(requests,1,'ingredient Check starts a detailed search despite false cache')
  eq(lastRequest,200,'ingredient Check queries its selected item')
  F.ahOpen=false; fire('COMMODITY_SEARCH_RESULTS_UPDATED',200)
  eq(F.depth[200].complete,true,'visible AH permits capturing complete search results')
  eq(F.BatchQuote(200,3),60,'checked batch quote uses prices captured at the visible AH')
  F.ahOpen=false; F.ScanFarms()
  eq(searches,2,'farm scan uses the same visible-window gate')
  F.ahOpen=false; F.ObserveRecipeDeals()
  eq(#F.DealList(),1,'visible AH permits observing current recipe bargains')
  F.CaptureDepth('commodity',200)

  -- A stale true event flag must not authorize searches or retain quotes at a closed AH.
  AuctionHouseFrame:Hide(); F.ahOpen=true
  F.ScanCraftPrices()
  eq(searches,2,'hidden modern AH blocks Scan despite stale true cache')
  eq(F.IsAuctionHouseOpen(),false,'hidden existing AH frame overrides stale true cache')
  eq(next(F.depth),nil,'detecting a missed close discards detailed prices')
  eq(next(F.deals),nil,'detecting a missed close discards recipe bargains')
  eq(F.BatchQuote(200,3),nil,'closed AH cannot reuse a previously checked batch')
  F.RequestDepth(200); eq(requests,1,'closed AH blocks new ingredient searches')
  eq(F.Deposit(100,2,1),nil,'closed AH does not request a live deposit')
  F.ScanFarms(); eq(searches,2,'closed AH also blocks farm scans')
  fire('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED')
  eq(next(F.deals),nil,'late browse update after close cannot resurrect recipe bargains')

  -- A missed reopen must clear the previous visit before BatchQuote reads its
  -- local book; reading the book first would retain a stale table reference.
  AuctionHouseFrame:Show(); F.ahOpen=false
  F.depth[200]={complete=true,kind='commodity',seen=time(),lots={{price=20,quantity=100}}}
  eq(F.BatchQuote(200,3),nil,'missed reopen invalidates an old book before BatchQuote can use it')
  eq(F.depth[200],nil,'missed reopen removes the prior visit book from the cache')

  -- Either visible frame satisfies Auctionator; an event alone cannot do so.
  AuctionHouseFrame=nil; AuctionFrame=widget(); F.ahOpen=false
  F.ScanCraftPrices(); eq(searches,3,'visible legacy AuctionFrame also permits Scan')
  AuctionHouseFrame=widget(); AuctionHouseFrame:Hide()
  eq(F.IsAuctionHouseOpen(),true,'visible legacy window wins when modern window is hidden')
  AuctionFrame:Hide(); AuctionHouseFrame:Show()
  eq(F.IsAuctionHouseOpen(),true,'visible modern window wins when legacy window is hidden')
  AuctionHouseFrame=nil; AuctionFrame=nil; F.SetAuctionHouseOpen(false)
  fire('AUCTION_HOUSE_SHOW')
  eq(F.IsAuctionHouseOpen(),false,'SHOW event alone cannot authorize Auctionator without an AH frame')
  F.ScanCraftPrices(); eq(searches,3,'Scan cannot call Auctionator when no AH frame exists')
  eq(searches,3,'AH SHOW event never starts Auctionator automatically')
  fire('AUCTION_HOUSE_CLOSED')
  eq(F.IsAuctionHouseOpen(),false,'CLOSED event clears auction interaction state')
  AuctionHouseFrame=widget(); AuctionHouseFrame:Hide()

  fire('PLAYER_INTERACTION_MANAGER_FRAME_SHOW',Enum.PlayerInteractionType.Merchant)
  eq(F.ahOpen,false,'merchant interaction SHOW leaves the auction state unchanged')
  eq(F.IsAuctionHouseOpen(),false,'merchant interaction SHOW cannot open auction access')
  AuctionHouseFrame:Show()
  fire('PLAYER_INTERACTION_MANAGER_FRAME_SHOW',Enum.PlayerInteractionType.Auctioneer)
  eq(F.ahOpen,true,'Auctioneer interaction SHOW records auction state directly')
  eq(F.IsAuctionHouseOpen(),true,'Auctioneer interaction SHOW establishes auction access')
  eq(searches,3,'Auctioneer interaction SHOW does not start a background scan')
  F.depth[200]={complete=true,kind='commodity',seen=time(),lots={{price=20,quantity=100}}}
  F.deals[900]={id=900,seen=time(),saving=5000}
  local oldBook=F.depth[200]
  fire('PLAYER_INTERACTION_MANAGER_FRAME_HIDE',Enum.PlayerInteractionType.Merchant)
  eq(F.IsAuctionHouseOpen(),true,'unrelated interaction HIDE does not close the AH')
  eq(F.depth[200],oldBook,'unrelated interaction HIDE preserves current ingredient data')
  AuctionHouseFrame:Hide()
  fire('PLAYER_INTERACTION_MANAGER_FRAME_HIDE',Enum.PlayerInteractionType.Auctioneer)
  eq(F.ahOpen,false,'Auctioneer interaction HIDE records closure before a query checks the frame')
  eq(next(F.depth),nil,'Auctioneer HIDE expires all ingredient quotes')
  eq(next(F.deals),nil,'Auctioneer HIDE expires all recipe deals')
  eq(F.IsAuctionHouseOpen(),false,'Auctioneer interaction HIDE closes auction access')
  eq(searches,3,'closing interactions never starts Auctionator')
  eq(requests,1,'open and close interactions never initiate detailed ingredient searches')

  AuctionHouseFrame:Show(); fire('PLAYER_INTERACTION_MANAGER_FRAME_SHOW',Enum.PlayerInteractionType.Auctioneer)
  eq(F.BatchQuote(200,3),nil,'reopening cannot reuse quotes from the prior visit')
  unitPrice=30; F.RequestDepth(200); fire('COMMODITY_SEARCH_RESULTS_UPDATED',200)
  eq(requests,2,'new visit fetches fresh detailed data only after Check')
  eq(F.BatchQuote(200,3),90,'new visit uses newly fetched prices')
  F.ahOpen=false
  F.depth[200]=oldBook; F.deals[900]={id=900,seen=time(),saving=5000}
  F.SetAuctionHouseOpen(false)
  eq(next(F.depth),nil,'an already-false state still discards stray old quotes')
  eq(next(F.deals),nil,'an already-false state still discards stray old deals')

  AuctionHouseFrame:Hide()
  Enum.PlayerInteractionType=nil
  fire('PLAYER_INTERACTION_MANAGER_FRAME_SHOW',21)
  eq(F.ahOpen,false,'missing interaction enums leave event state unchanged')
  eq(F.IsAuctionHouseOpen(),false,'missing interaction enums cannot accidentally authorize AH access')
  F.FarmProviders=providers; F.FarmCandidates=candidates; F.FarmSources=sources; F.FarmLevel=level
  F.Say=say
end
