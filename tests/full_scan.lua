-- Full-server snapshots: no partial publication or checked-stock claims.
return function(F,eq,fire,widget)
  local savedGlobals,savedFields={},{}
  for _,key in ipairs({'C_AuctionHouse','C_Timer','C_Item','GetItemInfoInstant','AuctionHouseFrame','AuctionFrame','Auctionator','time','GetRealmName','GetCurrentRegion','UnitFactionGroup','UnitFullName','UnitName','hooksecurefunc','MobAuctionDB'}) do savedGlobals[key]={_G[key]} end
  for _,key in ipairs({'db','window','details','fullScanState','OnFullScanComplete','ItemInfo','ahOpen','priceCache','auctionRecipes'}) do savedFields[key]={F[key]} end
  local clock,realm=3000000,'TestRealm'
  time=function() return clock end
  GetRealmName=function() return realm end
  GetCurrentRegion=function() return 1 end
  UnitFactionGroup=function() return 'Horde' end
  UnitFullName=function() return 'Dazed','TestRealm' end
  UnitName=function() return 'Dazed' end
  AuctionHouseFrame=widget(); AuctionHouseFrame:Show(); AuctionFrame=nil
  Auctionator={SavedState={}}
  local timers,requests,loads={},0,0
  C_Timer={After=function(delay,fn) timers[#timers+1]={at=clock+delay,fn=fn} end}
  local function tick()
    if #timers==0 then return false end
    table.sort(timers,function(a,b) return a.at<b.at end)
    local timer=table.remove(timers,1); clock=timer.at; timer.fn(); return true
  end
  local function drain()
    local count=0
    while tick() do count=count+1; assert(count<1000,'full scan timer work must be bounded') end
  end
  local rows,metadata,instant={},{},{}
  local throwRequest=false
  C_AuctionHouse={
    ReplicateItems=function() if throwRequest then error('refused') end; requests=requests+1 end,
    GetNumReplicateItems=function() return #rows end,
    GetReplicateItemInfo=function(index)
      local r=rows[index+1]
      if not r or r.invalid then return nil end
      return r.name or ('Item '..r.id),nil,r.quantity or 1,1,true,1,nil,1,1,r.buyout or 0,0,nil,nil,r.owner,r.fullName,r.sold or 0,r.id,r.hasAllInfo~=false
    end,
  }
  C_Item={RequestLoadItemDataByID=function() loads=loads+1 end}
  local function instantInfo(id)
    local data=instant[id]
    if data then return data.id or id,'type','subtype','',1,data.class,data.subclass end
  end
  C_Item.GetItemInfoInstant=instantInfo; GetItemInfoInstant=nil
  F.ItemInfo=function(id)
    if metadata[id]==false then return nil end
    return 'Item '..id,nil,nil,nil,nil,nil,nil,nil,nil,nil,1,id==900 and 9 or 7,id==900 and 4 or 0
  end
  hooksecurefunc=function(tbl,key,fn)
    local original=tbl[key]
    tbl[key]=function(...) local results={original(...)}; fn(...); return unpack(results) end
  end
  F.window=nil; F.details=nil
  local commits=0; local published
  F.OnFullScanComplete=function(snapshot) commits=commits+1; published=snapshot end
  if not F.StartFullScan then assert(loadfile('MobAuction/FullScan.lua'))('MobAuction',F) end
  local function reset()
    F.CancelFullScan(); timers={}; clock=clock+901
    realm='TestRealm'; rows={}; metadata={}; instant={}; requests=0; loads=0; commits=0; published=nil; throwRequest=false
    C_Item.GetItemInfoInstant=instantInfo; GetItemInfoInstant=nil
    MobAuctionDB={scanForecastsEnabled=true,assumedDeposit=100,setupComplete=true,maxAge=1}
    F.Init(); AuctionHouseFrame:Show(); F.ahOpen=true; F.fullScanState=nil
    Auctionator.SavedState={}
  end
  reset()
  rows={
    {id=100,quantity=4,buyout=280,owner='Other'},
    {id=100,quantity=1,buyout=100,owner='Other'},
    {id=900,quantity=5,buyout=5000,owner='Other'},
    {id=900,quantity=1,buyout=1500,owner='Other'},
    {id=100,quantity=1,buyout=1,owner='Dazed'},
    {id=101,quantity=2,buyout=0,owner='Other'},
    {id=102,quantity=1,buyout=80,sold=1,owner='Other'},
    {id=103,quantity=2,buyout=90},
    {id=104,quantity=1,buyout=100,owner='Dazed',fullName='Dazed-AnotherRealm'},
  }
  eq(F.StartFullScan(),true,'one explicit action requests the full server AH snapshot')
  eq(requests,1,'full scan uses one ReplicateItems request')
  eq(F.StartFullScan(),false,'duplicate full scan cannot start while waiting')
  eq(F.GetFullScanSnapshot(),nil,'waiting for data never publishes guessed prices')
  fire('REPLICATE_ITEM_LIST_UPDATE'); drain()
  eq(commits,1,'completed full snapshot is published exactly once')
  eq(published.total,9,'snapshot records every server listing in its coverage count')
  eq(published.buyoutRows,6,'only auctionable buyout rows contribute prices')
  eq(published.own,1,'current character own listing is excluded')
  eq(published.bidOnly,1,'bid-only listing is counted without inventing buyout price')
  eq(published.sold,1,'sold listing is excluded from current prices')
  eq(published.items[100].minUnit,70,'whole-stack buyout is divided by the actual stack quantity')
  eq(published.items[100].quantity,5,'snapshot counts available units from nonowned buyout listings')
  eq(published.items[900].minUnit,1000,'recipe unit minimum can differ from cheapest whole purchase')
  eq(published.items[900].minBuyout,1500,'recipe purchase quote retains the cheapest whole lot cost')
  eq(published.items[900].class,9,'recipe classification is available to learning research')
  eq(published.items[103].ownerUnknown,true,'missing owner remains explicitly unknown')
  eq(published.items[104]~=nil,true,'same-name seller on another realm is not mistaken for the player')
  eq(F.FullScanPrice(100),70,'full scan price supplies an item-ID forecast')
  eq(F.FullScanPrice(999),nil,'absent item has no full snapshot price')
  eq(F.GetFullScanSnapshot()~=nil,true,'fresh committed snapshot lets caller distinguish absence from no snapshot')
  eq(F.StartFullScan(),false,'full scan respects the server cooldown after completion')
  local snapshot=published
  F.db.maxAge=0; clock=snapshot.seen+30
  eq(F.FullScanPrice(100),70,'zero-day freshness permits a current open-AH quote')
  clock=snapshot.seen+61; eq(F.GetFullScanSnapshot(),nil,'zero-day quote expires after sixty seconds')
  F.db.maxAge=1; clock=snapshot.seen+86400
  eq(F.FullScanPrice(100),70,'one-day limit permits the exact age boundary')
  clock=clock+1; eq(F.GetFullScanSnapshot(),nil,'one-day limit never rounds almost two days down to one')
  clock=snapshot.seen-1; eq(F.GetFullScanSnapshot(),nil,'future-dated snapshot is rejected')
  clock=snapshot.seen+1; realm='DifferentRealm'; eq(F.GetFullScanSnapshot(),nil,'prices cannot cross realm markets')
  realm='TestRealm'; snapshot.build='old-build'; eq(F.GetFullScanSnapshot(),nil,'old-build snapshot is rejected')

  reset(); rows={{id=900,quantity=1,buyout=1500}}; metadata[900]=false
  F.StartFullScan(); fire('REPLICATE_ITEM_LIST_UPDATE')
  eq(commits,0,'loading recipe metadata does not publish partial coverage')
  eq(loads>0,true,'missing item metadata requests client item loading')
  metadata[900]=true; drain()
  eq(commits,1,'later item data completes the same snapshot without another server request')
  eq(published.buyoutRows,1,'retried row is not counted twice')

  reset(); rows={{id=900,name='Uncached plans',buyout=1500,hasAllInfo=false}}; metadata[900]=false
  instant[900]={class=9,subclass=4}
  F.StartFullScan(); fire('REPLICATE_ITEM_LIST_UPDATE')
  eq(commits,1,'local instant classification lets an uncached AH recipe complete immediately')
  eq(published.items[900].name,'Uncached plans','replicate item name fills a missing GetItemInfo name')
  eq(published.items[900].class,9,'instant item tuple supplies recipe class from return six')
  eq(published.items[900].subclass,4,'instant item tuple supplies profession subclass from return seven')
  eq(published.items[900].ownerUnknown,true,'incomplete optional row fields do not invent verified ownership')
  eq(loads,0,'valid required instant data avoids loading the entire AH item cache')

  reset(); rows={{id=900,buyout=1500}}; metadata[900]=false; instant[900]={class=9,subclass=4}
  C_Item.GetItemInfoInstant=nil; GetItemInfoInstant=instantInfo
  F.StartFullScan(); fire('REPLICATE_ITEM_LIST_UPDATE')
  eq(commits,1,'legacy global instant classification is supported when the namespace API is absent')

  reset(); rows={{id=900,buyout=1500},{id=900,buyout=2000}}; metadata[900]=false
  instant[900]={id=901,class=9,subclass=4}
  local requestTime=clock
  F.StartFullScan(); fire('REPLICATE_ITEM_LIST_UPDATE')
  while clock<requestTime+12 do tick() end
  eq(commits,0,'mismatched instant identity cannot classify a recipe row')
  eq(F.fullScanState.phase,'loading','genuinely missing data can finish after the former four-second retry window')
  eq(loads,1,'repeated listings request each missing item cache only once')
  instant[900].id=900; drain()
  eq(commits,1,'delayed instant metadata completes the same snapshot within its bounded deadline')
  eq(published.items[900].listings,2,'metadata retry preserves both listings without duplication')

  reset(); rows={{id=900,buyout=1500}}; metadata[900]=false; requestTime=clock
  F.StartFullScan(); fire('REPLICATE_ITEM_LIST_UPDATE'); drain()
  eq(commits,0,'permanently missing classification never publishes incomplete coverage')
  eq(clock-requestTime,180,'missing metadata gets the full bounded reading deadline')
  eq(F.fullScanState.phase,'incomplete','metadata deadline gives an explicit incomplete result')

  reset(); rows={{id=100,buyout=100}}; F.StartFullScan(); fire('REPLICATE_ITEM_LIST_UPDATE'); drain()
  local previous=F.db.fullScan
  clock=clock+901; rows={{id=100,buyout=50},{invalid=true}}
  F.StartFullScan(); fire('REPLICATE_ITEM_LIST_UPDATE'); drain()
  eq(F.db.fullScan,previous,'invalid row leaves the prior complete snapshot intact')
  eq(F.fullScanState.phase,'incomplete','unresolved rows are reported as an incomplete scan')
  eq(F.fullScanState.missing,1,'incomplete status reports unresolved listing count')
  eq(F.FullScanPrice(100),100,'partial new minimum cannot replace the previous complete price')

  reset(); rows={}; F.StartFullScan(); fire('REPLICATE_ITEM_LIST_UPDATE'); drain()
  eq(commits,0,'empty server reply cannot silently publish complete empty coverage')
  eq(F.fullScanState.phase,'incomplete','empty server reply is explained')
  reset(); F.StartFullScan(); drain()
  eq(F.fullScanState.phase,'incomplete','no response times out rather than hanging forever')
  eq(F.db.fullScan,nil,'timeout cannot fabricate a snapshot')
  reset(); throwRequest=true
  eq(F.StartFullScan(),false,'API request exception returns failure')
  eq(F.fullScanState.phase,'incomplete','request error has explicit status')

  reset(); rows={}
  for i=1,600 do rows[i]={id=100+i,buyout=i} end
  F.StartFullScan(); fire('REPLICATE_ITEM_LIST_UPDATE')
  eq(commits,0,'large snapshot yields before committing')
  eq(F.fullScanState.processed,250,'large snapshot work is bounded per frame')
  AuctionHouseFrame:Hide(); fire('AUCTION_HOUSE_CLOSED'); drain()
  eq(commits,0,'closing AH cancels queued snapshot processing')
  eq(F.fullScanState.phase,'cancelled','closed AH scan reports cancellation')
  eq(F.StartFullScan(),false,'full scan cannot start with a closed auction window')

  reset(); rows={{id=100,buyout=75}}
  fire('REPLICATE_ITEM_LIST_UPDATE'); drain()
  eq(commits,1,'another addon completed server snapshot can be shared')
  eq(requests,0,'sharing another addon snapshot does not send another request')
  eq(published.source,'Shared client full scan','shared snapshot records its source')
  reset(); Auctionator.SavedState.TimeOfLastReplicateScan=clock
  eq(F.StartFullScan(),false,'Auctionator recent full scan shares the cooldown')
  eq(requests,0,'shared cooldown avoids an unnecessary server request')

  reset(); for i=1,600 do rows[i]={id=i,buyout=100} end
  F.StartFullScan(); fire('REPLICATE_ITEM_LIST_UPDATE')
  C_AuctionHouse.ReplicateItems(); drain()
  eq(commits,0,'another replicate request cannot mix two snapshots during processing')
  eq(F.fullScanState.phase,'incomplete','replaced replication data leaves an explicit failed scan')

  F.CancelFullScan(); timers={}
  for key,value in pairs(savedGlobals) do _G[key]=value[1] end
  for key,value in pairs(savedFields) do F[key]=value[1] end
end
