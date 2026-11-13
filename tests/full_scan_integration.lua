-- Exercise the actual full scan, pricing, depth and recipe-offer handoff together.
return function(F,eq,fire,widget)
  local savedGlobals,savedFields={},{}
  for _,key in ipairs({'C_AuctionHouse','C_Timer','C_Item','AuctionHouseFrame','AuctionFrame','Auctionator','AHledgerAPI','time',
      'GetRealmName','GetCurrentRegion','UnitFactionGroup','UnitFullName','UnitName','hooksecurefunc','MobAuctionDB'}) do savedGlobals[key]={_G[key]} end
  for _,key in ipairs({'db','window','details','scanStatusLabel','fullScanState','ItemInfo','ahOpen','priceCache','depth','depthRequests',
      'depositQuotes','auctionRecipes','fullScanRecipes','Refresh','RefreshDetails','ObserveFullScanRecipes','deals'}) do savedFields[key]={F[key]} end
  if not F.StartFullScan then assert(loadfile('MobAuction/FullScan.lua'))('MobAuction',F) end
  local now=6000000
  time=function() return now end
  GetRealmName=function() return 'IntegrationRealm' end
  GetCurrentRegion=function() return 1 end
  UnitFactionGroup=function() return 'Horde' end
  UnitFullName=function() return 'Dazed','IntegrationRealm' end
  UnitName=function() return 'Dazed' end
  AuctionHouseFrame=widget(); AuctionHouseFrame:Show(); AuctionFrame=nil
  F.window=widget(); F.details=widget(); F.scanStatusLabel=widget()
  local timers,requests={},0
  C_Timer={After=function(delay,fn) timers[#timers+1]={at=now+delay,fn=fn} end}
  local function finishWork()
    local count=0
    while #timers>0 do
      table.sort(timers,function(a,b) return a.at<b.at end)
      if timers[1].at>now+30 then break end -- Keep the obsolete request timeout queued.
      local timer=table.remove(timers,1); now=timer.at; timer.fn()
      count=count+1; assert(count<100,'integration scan work must stay bounded')
    end
  end
  local rows={
    {id=100,count=1,buyout=900}, {id=200,count=10,buyout=700},
    {id=201,count=5,buyout=300}, {id=900,count=2,buyout=2400}, {id=900,count=1,buyout=1500},
  }
  for i=1,250 do rows[#rows+1]={id=200,count=1,buyout=80} end
  C_AuctionHouse={
    ReplicateItems=function() requests=requests+1 end,
    GetNumReplicateItems=function() return #rows end,
    GetReplicateItemInfo=function(index)
      local r=rows[index+1]
      return 'Item '..r.id,nil,r.count,1,true,1,nil,1,1,r.buyout,0,nil,nil,'Other','Other-IntegrationRealm',0,r.id,true
    end,
  }
  hooksecurefunc=function(tbl,key,fn)
    local original=tbl[key]
    tbl[key]=function(...) local results={original(...)}; fn(...); return unpack(results) end
  end
  C_Item={RequestLoadItemDataByID=function() end}
  F.ItemInfo=function(id) return 'Item '..id,nil,nil,nil,nil,nil,nil,nil,nil,nil,1,id==900 and 9 or 7,id==900 and 4 or 0,0 end
  local auctionatorCalls,ledgerCalls=0,0
  Auctionator={SavedState={},API={v1={
    GetAuctionPriceByItemID=function(_,id) auctionatorCalls=auctionatorCalls+1; return id==404 and 12 or 1 end,
    GetAuctionAgeByItemID=function() return 0 end,
  }}}
  AHledgerAPI={GetPrice=function() ledgerCalls=ledgerCalls+1; return {minBuyout=9,updated=now,snapshot=false} end}
  MobAuctionDB={scanForecastsEnabled=true,strictCosts=false,assumedDeposit=100,setupComplete=true,maxAge=1}
  F.Init(); F.ahOpen=true
  F.priceCache={[404]={3,'Old cached price'}}
  F.depth={[200]={complete=true,kind='commodity',seen=now,lots={{price=1,quantity=999}}}}
  F.depthRequests={[200]={itemID=200}}
  local observations,refreshes,detailRefreshes=0,0,0
  local observe=F.ObserveFullScanRecipes
  F.ObserveFullScanRecipes=function(snapshot) observations=observations+1; return observe(snapshot) end
  F.Refresh=function() refreshes=refreshes+1 end
  F.RefreshDetails=function() detailRefreshes=detailRefreshes+1 end

  eq(F.Scan(),true,'main scan action reaches the complete server snapshot scanner')
  eq(requests,1,'main scan action issues exactly one full AH request')
  eq(F.scanStatusLabel:GetText():find('Requesting',1,true)~=nil,true,'scan status immediately describes the server request')
  local beforeRefresh,beforeDetails=refreshes,detailRefreshes
  fire('REPLICATE_ITEM_LIST_UPDATE')
  eq(observations,0,'learning does not receive a partial multi-frame scan')
  eq(F.scanStatusLabel:GetText():find('250 / 255',1,true)~=nil,true,'scan status shows chunk progress without reevaluating recipes')
  eq(refreshes,beforeRefresh,'chunk progress avoids reevaluating every craft')
  finishWork()
  eq(observations,1,'completed scanner reaches Sources learning callback exactly once')
  eq(refreshes-beforeRefresh,1,'completion refreshes craft forecasts exactly once')
  eq(detailRefreshes-beforeDetails,1,'completion refreshes recipe details exactly once')
  eq(F.scanStatusLabel:GetText():find('Full AH snapshot:',1,true)~=nil,true,'completion status shows the committed snapshot')
  eq(next(F.priceCache),nil,'completion removes stale price cache entries')
  eq(next(F.depth),nil,'completion removes older checked listing books')
  eq(next(F.depthRequests),nil,'completion removes older detail request tracking')
  eq(F.fullScanRecipes[900].price,1500,'learning receives the cheapest entire recipe lot rather than per-unit stack price')
  eq(F.fullScanRecipes[900].snapshot,true,'recipe offer retains its snapshot provenance')
  eq(F.fullScanRecipes[200],nil,'material auctions cannot become recipe offers')

  local value,source,warning,evidence=F.MarketPrice(200)
  eq(value,70,'snapshot ingredient minimum overrides older addon prices')
  eq(source,'Full AH snapshot','pricing reports the actual full-scan source')
  eq(type(warning),'string','snapshot price keeps its current-availability qualification')
  F.priceCache[404]={3,'Old cached price'}
  value,source=F.MarketPrice(404)
  eq(value,nil,'snapshot absence blocks a previously cached price')
  eq(source,'No purchasable listing in the full AH snapshot','snapshot absence explains why no price is available')
  eq(auctionatorCalls,0,'complete snapshot absence cannot revive stale Auctionator listings')
  eq(ledgerCalls,0,'complete snapshot absence cannot revive stale AHledger listings')

  value,source,warning,evidence=F.ForecastQuote(200,2,true)
  eq(value,140,'ingredient forecast multiplies the snapshot unit price by required units')
  eq(source,'Full AH snapshot','ingredient forecast keeps the snapshot source')
  eq(evidence.kind,'estimate','snapshot quantity never earns checked-stock evidence')
  value,source,warning,evidence=F.ForecastQuote(100,2,false)
  eq(value,1800,'sale forecast uses the snapshot output price and output quantity')
  eq(evidence.kind,'estimate','sale forecast remains estimated')
  F.db.vendors[2692]={price=200,bundle=5,seen=now,name='Spice vendor'}
  value,source,warning,evidence=F.ForecastQuote(2692,3,true)
  eq(value,200,'supplier-only reagent buys a whole bundle despite snapshot absence')
  eq(source,'Vendor: Spice vendor','supplier-only ingredient source remains visible')
  eq(evidence.kind,'vendor','observed supplier price keeps supplier evidence')
  eq(F.ForecastQuote(2692,6,true),400,'supplier forecast rounds up each required bundle')
  F.db.vendors[201]={price=200,bundle=5,seen=now,name='Supplier'}
  value,source,warning,evidence=F.ForecastQuote(201,3,true)
  eq(value,180,'cheaper AH ingredient forecast can beat a whole supplier bundle')
  eq(evidence.kind,'estimate','cheaper AH minimum is still a quantity forecast')
  value,source,warning,evidence=F.ForecastQuote(201,4,true)
  eq(value,200,'whole supplier bundle beats a higher AH quantity forecast')
  eq(evidence.kind,'vendor','choosing a supplier retains supplier evidence')
  F.db.vendors[2692].seen=now-7*86400-1
  eq(F.ForecastQuote(2692,3,true),nil,'expired supplier observation cannot fill a missing snapshot price')
  F.db.vendors[2692].seen=now

  F.depth[200]={complete=true,kind='commodity',seen=now,lots={{price=70,quantity=1}}}
  value,source,warning,evidence=F.ForecastQuote(200,2,true)
  eq(value,nil,'fresh checked stock shortage blocks snapshot quantity extrapolation')
  eq(source,'Insufficient purchasable stock','fresh stock shortage is explained')
  eq(evidence.kind,'missing','fresh shortage remains missing purchase evidence')
  F.depth[200]={complete=false,kind='commodity',seen=now,lots={{price=70,quantity=10}}}
  value,source=F.ForecastQuote(200,2,true)
  eq(value,nil,'pending partial depth results cannot be bypassed with the old snapshot')
  eq(source,'Incomplete search results','partial depth explains the blocked price')
  F.depth[200]={complete=true,kind='commodity',seen=now,lots={{price=100,quantity=10}}}
  value,source,warning,evidence=F.ForecastQuote(200,2,true)
  eq(value,200,'fresh more expensive depth overrides a cheaper snapshot minimum')
  eq(evidence.kind,'depth','current quantity quote retains depth evidence')
  F.db.vendors[201]=nil
  F.depth[201]={complete=true,kind='item',seen=now,lots={{price=400,quantity=5}}}
  eq(F.ForecastQuote(201,2,true),400,'fresh whole-lot quote cannot be split by snapshot unit minimum')
  F.depth[200].seen=now-61
  value,source,warning,evidence=F.ForecastQuote(200,2,true)
  eq(value,140,'expired depth can fall back to a still-fresh complete snapshot forecast')
  eq(evidence.kind,'estimate','expired checked stock loses its checked evidence')
  F.db.strictCosts=true
  eq(F.Quote(200,2,true),nil,'explicit checked-only pricing never substitutes snapshot quantities')
  F.db.strictCosts=false
  F.depth={}
  local recipe={id=123,output=100,made=1,reagents={{itemID=200,qty=2},{itemID=2692,qty=3}}}
  local result=F.Evaluate(recipe,{crafts=1,cut=5,failures=1,duration=1},F.Quote,F.Deposit)
  eq(result.cost,340,'full-scan craft calculation combines AH meat and whole supplier spice bundle')
  eq(result.profit,515,'full-scan craft profit subtracts reagent purchases and auction cut')
  eq(result.adjusted,415,'full-scan adjusted profit subtracts the requested assumed failed deposit')
  eq(result.estimated,true,'full-scan profitable craft remains an honest forecast')

  AuctionHouseFrame:Hide(); F.IsAuctionHouseOpen()
  eq(F.MarketPrice(200),70,'a fresh completed snapshot remains useful after leaving the AH')
  eq(F.fullScanRecipes[900].price,1500,'leaving the AH preserves snapshot recipe research')
  now=now+86401; F.priceCache={}
  eq(F.GetFullScanSnapshot(),nil,'expired full snapshot no longer claims complete current coverage')
  value,source=F.MarketPrice(404)
  eq(value,12,'without a usable full snapshot the normal recent addon fallback is available')
  eq(source,'Auctionator (0d old)','fallback clearly identifies its different price source')

  F.CancelFullScan(); timers={}
  for key,value in pairs(savedGlobals) do _G[key]=value[1] end
  for key,value in pairs(savedFields) do F[key]=value[1] end
end
