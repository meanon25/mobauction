-- Exact game deposit quotes: no hardcoded rates or fabricated ItemLocations.
return function(F,eq,fire,widget)
  for _,key in ipairs({'window','setup','report','details','settings'}) do
    if F[key] then F[key].suppressReturn=true; F[key]:Hide(); F[key].suppressReturn=nil end
  end
  local oldTime,oldBuild=time,F.Build
  local oldAH,oldContainer,oldLocation=C_AuctionHouse,C_Container,ItemLocation
  local oldSlots,oldStatuses=NUM_TOTAL_EQUIPPED_BAG_SLOTS,Enum.ItemCommodityStatus
  local clock,build=2000000,'deposit-build-a'
  time=function() return clock end; F.Build=function() return build end
  Enum.ItemCommodityStatus={Unknown=0,Item=1,Commodity=2}
  NUM_TOTAL_EQUIPPED_BAG_SLOTS=5
  MobAuctionDB={scanForecastsEnabled=true,strictCosts=true,assumedDeposit=false,setupComplete=true}; F.Init()
  AuctionHouseFrame=widget(); AuctionFrame=nil; F.SetAuctionHouseOpen(false)
  local bags={[0]={[1]=200,[2]=300,[3]=301},[5]={[1]=202}}
  C_Container={
    GetContainerNumSlots=function(bag) return bags[bag] and #bags[bag] or 0 end,
    GetContainerItemID=function(bag,slot) return bags[bag] and bags[bag][slot] end,
  }
  ItemLocation={CreateFromBagAndSlot=function(_,bag,slot) return {bag=bag,slot=slot} end}
  local commodityCalls,itemCalls={},{}
  local commodityValue,itemUnit,loadResult=nil,7,nil
  local function commodity(id,duration,quantity)
    commodityCalls[#commodityCalls+1]={id=id,duration=duration,quantity=quantity}
    if id==400 then return loadResult end
    if id==401 then return -1 end
    if id==402 then return math.huge end
    if id==403 then return '100' end
    if id==404 then error('Game data not ready') end
    if id==405 then return 0/0 end
    return commodityValue or duration*100+quantity*quantity
  end
  C_AuctionHouse={
    MakeItemKey=function(id) return {itemID=id} end,
    GetItemKeyInfo=function(key)
      if key.itemID==300 or key.itemID==301 then return nil end
      return {isCommodity=key.itemID==100 or key.itemID>=400}
    end,
    CalculateCommodityDeposit=commodity,
    GetItemCommodityStatus=function(location)
      local id=bags[location.bag][location.slot]
      return id==300 and 2 or (id==301 and 0 or 1)
    end,
    CalculateItemDeposit=function(location,duration,quantity)
      itemCalls[#itemCalls+1]={bag=location.bag,slot=location.slot,duration=duration,quantity=quantity}
      return duration*itemUnit+quantity
    end,
  }

  eq(F.Deposit(100,2,1),104,'commodity quote works without owning its output')
  eq(commodityCalls[1].id,100,'commodity API receives output item ID')
  eq(commodityCalls[1].duration,1,'commodity API receives duration index')
  eq(commodityCalls[1].quantity,2,'commodity API receives exact total output quantity')
  eq(F.Deposit(100,3,1),109,'commodity batch quote is not extrapolated from a unit quote')
  eq(F.Deposit(100,2,2),204,'a changed duration gets its own exact quote')
  local calls=#commodityCalls
  local amount,source=F.Deposit(100,2,1)
  eq(amount,104,'same quantity and duration reuse the observed game quote')
  eq(#commodityCalls,calls,'repeated forecast avoids a duplicate deposit API request')
  eq(source:find('cached this AH visit',1,true)~=nil,true,'cached quote provenance remains visible')

  commodityValue=999; clock=clock+61
  eq(F.Deposit(100,2,1),999,'quotes older than one minute are refreshed')
  commodityValue=888; clock=clock-120
  eq(F.Deposit(100,2,1),888,'future-dated observations are not reused')
  commodityValue=777; build='deposit-build-b'
  eq(F.Deposit(100,2,1),777,'a different client build cannot reuse an old deposit observation')
  commodityValue=nil

  -- Metadata is enough for commodity classification; the bag enum is optional.
  F.depositQuotes={}; Enum.ItemCommodityStatus=nil
  eq(F.Deposit(100,2,1),104,'ID-based commodity quotes do not require the bag-status enum')
  Enum.ItemCommodityStatus={Unknown=0,Item=1,Commodity=2}
  eq(F.Deposit(300,2,1),104,'owned commodity status can recover missing item-key metadata')
  calls=#itemCalls
  eq(F.Deposit(301,2,1),nil,'unknown bag commodity status does not guess an item deposit')
  eq(#itemCalls,calls,'unknown commodity status never enters CalculateItemDeposit')
  eq(F.Deposit(201,2,1),nil,'noncommodity without an owned output remains unknown')
  eq(#itemCalls,calls,'missing output cannot fabricate an ItemLocation')

  amount,source=F.Deposit(200,4,1)
  eq(amount,32,'noncommodity forecast totals four separately quoted one-item listings')
  eq(itemCalls[#itemCalls].bag,0,'noncommodity quote uses the actual output bag')
  eq(itemCalls[#itemCalls].slot,1,'noncommodity quote uses the actual output slot')
  eq(itemCalls[#itemCalls].quantity,1,'noncommodity model requests one listing unit from the game')
  eq(source:find('4 individual listings',1,true)~=nil,true,'noncommodity listing assumption is explicit')
  calls=#itemCalls
  eq(F.Deposit(200,5,1),40,'individual listing unit quote can total a different number of listings')
  eq(#itemCalls,calls,'individual batch planning reuses the exact one-item listing quote')
  eq(F.Deposit(202,1,1),8,'equipped reagent bag is included when the client exposes it')
  eq(itemCalls[#itemCalls].bag,5,'extra equipped bag location reaches the game API')

  -- Failure is unknown, never free; an actual returned zero is a valid quote.
  eq(F.Deposit(400,1,1),nil,'missing game quote remains unknown')
  loadResult=0
  eq(F.Deposit(400,1,1),0,'loading failure is not cached and a later real zero is accepted')
  calls=#commodityCalls
  eq(F.Deposit(400,1,1),0,'actual zero quote survives the cache lookup')
  eq(#commodityCalls,calls,'zero quote is cached like other valid game values')
  for _,id in ipairs({401,402,403,404,405}) do
    eq(F.Deposit(id,1,1),nil,'invalid or failed game deposit '..id..' remains unknown')
  end
  calls=#commodityCalls
  eq(F.Deposit(100,1.5,1),nil,'fractional listing quantity is rejected')
  eq(F.Deposit(100,1,4),nil,'unknown duration index is rejected')
  eq(F.Deposit(0/0,1,1),nil,'invalid item ID is rejected before cache indexing')
  eq(#commodityCalls,calls,'invalid requests never reach game calculation APIs')

  -- Newly crafted/moved bag items invalidate locations and update visible UI.
  local oldWindow,oldDetails,refresh,refreshDetails=F.window,F.details,F.Refresh,F.RefreshDetails
  local mainRefresh,detailRefresh=0,0
  F.window=widget(); F.details=widget()
  F.Refresh=function() mainRefresh=mainRefresh+1 end
  F.RefreshDetails=function() detailRefresh=detailRefresh+1 end
  itemUnit=11; fire('BAG_UPDATE_DELAYED')
  eq(next(F.depositQuotes),nil,'bag update discards cached location-dependent quotes')
  eq(mainRefresh,1,'bag update refreshes visible crafting forecasts')
  eq(detailRefresh,1,'bag update refreshes the visible ingredient detail window')
  eq(F.Deposit(200,4,1),48,'bag update permits a new exact item quote')
  F.window=oldWindow; F.details=oldDetails; F.Refresh=refresh; F.RefreshDetails=refreshDetails

  AuctionHouseFrame:Hide(); F.SetAuctionHouseOpen(false)
  eq(next(F.depositQuotes),nil,'closing the AH clears automatic deposit observations')
  calls=#commodityCalls
  eq(F.Deposit(100,2,1),nil,'closed AH does not reuse the last visit deposit')
  eq(#commodityCalls,calls,'closed AH never calls game deposit APIs')
  F.db.deposits[100]={[1]=50}
  eq(F.Deposit(100,3,1),150,'explicit manual per-unit override remains available outside AH')
  eq(F.Deposit(100,3,2),nil,'manual override applies only to its chosen duration')
  F.db.deposits[100][1]=0
  eq(F.Deposit(100,3,1),0,'explicit manual zero remains a valid override')
  F.db.deposits[100]=nil
  AuctionHouseFrame:Show(); F.SetAuctionHouseOpen(true)
  commodityValue=555
  eq(F.Deposit(100,2,1),555,'new AH visit obtains a new deposit rather than the previous quote')

  F.SetAuctionHouseOpen(false)
  time=oldTime; F.Build=oldBuild
  C_AuctionHouse=oldAH; C_Container=oldContainer; ItemLocation=oldLocation
  NUM_TOTAL_EQUIPPED_BAG_SLOTS=oldSlots; Enum.ItemCommodityStatus=oldStatuses
end
