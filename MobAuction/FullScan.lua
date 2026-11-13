local _, F = ...
-- ReplicateItems returns the server's entire AH snapshot in one response. Read
-- it over several frames, then commit once; partial data never replaces a scan.
local COOLDOWN, TIMEOUT, CHUNK, RETRY_DELAY = 900, 180, 250, 1
local active, hookedAPI, generation = nil, nil, 0
local events=CreateFrame('Frame')
local function integer(n) return type(n)=='number' and n>=0 and n<math.huge and n==math.floor(n) end
local function positive(n) return integer(n) and n>0 end
local function safe(fn,...) return F.Safe(fn,...) end
local function market()
  return table.concat({tostring(safe(GetCurrentRegion) or '?'),tostring(safe(GetRealmName) or '?'),tostring(safe(UnitFactionGroup,'player') or '?')},':')
end
local function refresh()
  if F.window and F.window:IsShown() and F.Refresh then F.Refresh() end
  if F.details and F.details:IsShown() and F.RefreshDetails then F.RefreshDetails() end
end
local function status(phase,message,job)
  F.fullScanState={phase=phase,message=message,total=job and job.total or 0,
    processed=job and job.index or 0,missing=job and job.missing or 0,time=time()}
  if F.db then F.db.fullScanAttempt=F.fullScanState end
  -- Progress should stay live without rebuilding thousands of craft forecasts
  -- for every chunk of the server response.
  if F.scanStatusLabel then F.scanStatusLabel:SetText(F.FullScanStatus and F.FullScanStatus() or message) end
end
local function schedule(delay,callback)
  if C_Timer and C_Timer.After then C_Timer.After(delay,callback); return end
  -- Older clients still yield a frame rather than recursively scanning the AH.
  local elapsed=0
  local timer=CreateFrame('Frame')
  timer:SetScript('OnUpdate',function(self,delta)
    elapsed=elapsed+delta
    if elapsed>=delay then self:SetScript('OnUpdate',nil); callback() end
  end)
end
function F.CancelFullScan(reason)
  if not active then return end
  local job=active; active=nil; generation=generation+1
  status('cancelled',reason or 'Full AH scan cancelled; previous completed prices were kept.',job)
end
local function failure(reason,job)
  if active~=job then return end
  active=nil; generation=generation+1
  status('incomplete',reason..' Previous completed prices were kept.',job)
  F.Say(F.fullScanState.message); refresh()
end
local function lastRequest()
  local latest,source=0,nil
  local saved=F.db and F.db.fullScanLastRequest
  if type(saved)=='table' and saved.market==market() and integer(saved.at) then latest,source=saved.at,'MobAuction' end
  local auctionator=Auctionator and Auctionator.SavedState
  if auctionator and integer(auctionator.TimeOfLastReplicateScan) and auctionator.TimeOfLastReplicateScan>latest then
    latest,source=auctionator.TimeOfLastReplicateScan,'Auctionator'
  end
  return latest,source
end
local function rememberRequest()
  if F.db then F.db.fullScanLastRequest={at=time(),market=market()} end
end
local function installHook()
  local api=C_AuctionHouse
  if not api or api==hookedAPI or type(hooksecurefunc)~='function' then return end
  local ok=pcall(hooksecurefunc,api,'ReplicateItems',function()
    rememberRequest()
    if active and active.phase=='reading' then
      failure('Another full scan request replaced the data while it was being read.',active)
    end
  end)
  if ok then hookedAPI=api end
end
local function owns(owner,fullName)
  local name,realm
  if UnitFullName then local ok; ok,name,realm=pcall(UnitFullName,'player'); if not ok then name=nil end end
  name=name or safe(UnitName,'player')
  realm=realm or safe(GetRealmName)
  if not name then return false end
  local function normalized(value) return type(value)=='string' and value:gsub('%s',''):lower() or nil end
  local short=normalized(name)
  if type(fullName)=='string' and fullName~='' and fullName:find('-',1,true) then
    return realm and normalized(fullName)==normalized(name..'-'..realm) or false
  end
  return normalized(owner)==short or normalized(fullName)==short
end
local function readRow(job,index)
  local ok,name,texture,count,quality,usable,level,levelType,minBid,minIncrement,buyout,bid,highBidder,bidderFullName,owner,ownerFullName,saleStatus,id,hasAllInfo=pcall(C_AuctionHouse.GetReplicateItemInfo,index)
  if not ok or not positive(id) or not positive(count) or not integer(buyout) then return false end
  if type(saleStatus)~='number' then return false end
  if saleStatus~=0 then job.sold=job.sold+1; return true end
  if owns(owner,ownerFullName) then job.own=job.own+1; return true end
  if buyout==0 then job.bidOnly=job.bidOnly+1; return true end
  local known=job.metadata[id]
  local itemName,class,subclass
  if known then itemName,class,subclass=known.name,known.class,known.subclass
  else
    local infoOK,link,rarity,itemLevel,minimumLevel,itemType,itemSubType,stack,equip,icon,sell
    infoOK,itemName,link,rarity,itemLevel,minimumLevel,itemType,itemSubType,stack,equip,icon,sell,class,subclass=pcall(F.ItemInfo,id)
    if not infoOK then itemName,class,subclass=nil,nil,nil end
    itemName=itemName or (type(name)=='string' and name~='' and name or nil)
    if not integer(class) or not integer(subclass) then
      -- The instant API reads local item classification without requiring every
      -- item in a large AH to finish its asynchronous GetItemInfo cache load.
      local instant=C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
      if type(instant)=='function' then
        local loaded,instantID,itemType,itemSubType,equip,icon,instantClass,instantSubclass=pcall(instant,id)
        if loaded and instantID==id then class,subclass=instantClass,instantSubclass end
      end
    end
  end
  if not itemName or not integer(class) or not integer(subclass) then
    if not job.requestedItems[id] and C_Item and C_Item.RequestLoadItemDataByID then
      job.requestedItems[id]=true; safe(C_Item.RequestLoadItemDataByID,id)
    end
    return false
  end
  job.metadata[id]={name=itemName,class=class,subclass=subclass}
  -- hasAllInfo also includes fields we do not need to price this row. Validate
  -- the required fields above; missing owner data stays explicitly unverified.
  local unknown=(type(owner)~='string' or owner=='') and (type(ownerFullName)~='string' or ownerFullName=='')
  local row=job.items[id]
  if not row then row={name=itemName,class=class,subclass=subclass,quantity=0,listings=0}; job.items[id]=row; job.itemCount=job.itemCount+1 end
  local unit=buyout/count
  row.minUnit=not row.minUnit and unit or math.min(row.minUnit,unit)
  row.minBuyout=not row.minBuyout and buyout or math.min(row.minBuyout,buyout)
  row.quantity=row.quantity+count; row.listings=row.listings+1
  row.ownerUnknown=row.ownerUnknown or unknown
  job.buyoutRows=job.buyoutRows+1
  if unknown then job.ownerUnknown=job.ownerUnknown+1 end
  return true
end
local process
local function finish(job)
  if active~=job then return end
  if safe(C_AuctionHouse.GetNumReplicateItems)~=job.total then failure('The full AH listing changed before it finished loading.',job); return end
  if job.missing>0 then
    failure(string.format('Full AH scan incomplete: %d of %d rows still lacked valid item or price data.',job.missing,job.total),job); return
  end
  local snapshot={complete=true,seen=job.seen,market=job.market,build=F.Build(),items=job.items,
    total=job.total,buyoutRows=job.buyoutRows,bidOnly=job.bidOnly,own=job.own,sold=job.sold,
    invalid=0,missing=0,itemCount=job.itemCount,ownerUnknown=job.ownerUnknown,source=job.source}
  F.db.fullScan=snapshot; F.priceCache={}; active=nil
  status('complete',string.format('Full AH scan complete: %d listings read; %d item prices. %d own, %d bid-only and %d sold listings excluded. Prices are snapshot forecasts; check stock before buying.',snapshot.total,snapshot.itemCount,snapshot.own,snapshot.bidOnly,snapshot.sold),job)
  if F.OnFullScanComplete then F.OnFullScanComplete(snapshot)
  else
    if F.ObserveFullScanRecipes then F.ObserveFullScanRecipes(snapshot) end
    refresh()
  end
  F.Say(F.fullScanState.message)
end
process=function(job)
  if active~=job then return end
  if not F.IsAuctionHouseOpen() then F.CancelFullScan('Full AH scan cancelled because the auction house closed.'); return end
  if time()-job.started>TIMEOUT then failure('Full AH scan timed out while reading the server response.',job); return end
  if safe(C_AuctionHouse.GetNumReplicateItems)~=job.total then failure('The full AH listing changed while it was being read.',job); return end
  local limit=math.min(job.index+CHUNK,job.total)
  for index=job.index,limit-1 do if not readRow(job,index) then job.pending[#job.pending+1]=index end end
  job.index=limit
  status('reading',string.format('Reading full AH scan: %d / %d listings.',job.index,job.total),job)
  if job.index<job.total then schedule(0.01,function() process(job) end); return end
  local function retry()
    if active~=job then return end
    if not F.IsAuctionHouseOpen() then F.CancelFullScan('Full AH scan cancelled because the auction house closed.'); return end
    if time()-job.started>=TIMEOUT then finish(job); return end
    if safe(C_AuctionHouse.GetNumReplicateItems)~=job.total then failure('The full AH listing changed while item data loaded.',job); return end
    -- Each pass is also chunked; missing item data cannot freeze a large scan.
    local remaining={}; local cursor=1
    local function step()
      if active~=job then return end
      if not F.IsAuctionHouseOpen() then F.CancelFullScan('Full AH scan cancelled because the auction house closed.'); return end
      if time()-job.started>=TIMEOUT then finish(job); return end
      local stop=math.min(cursor+CHUNK-1,#job.pending)
      for i=cursor,stop do local index=job.pending[i]; if not readRow(job,index) then remaining[#remaining+1]=index end end
      cursor=stop+1
      if cursor<=#job.pending then schedule(0.01,step); return end
      job.pending=remaining; job.missing=#remaining
      if job.missing==0 then finish(job)
      else
        status('loading',string.format('Full AH scan: waiting for valid data on %d listings; up to %d seconds remaining.',job.missing,math.max(0,math.ceil(TIMEOUT-(time()-job.started)))),job)
        schedule(RETRY_DELAY,retry)
      end
    end
    step()
  end
  job.missing=#job.pending
  if job.missing==0 then finish(job) else schedule(RETRY_DELAY,retry) end
end
local function receive()
  if not F.db or not F.IsAuctionHouseOpen() then return end
  if active and active.phase=='reading' then return end
  local total=safe(C_AuctionHouse and C_AuctionHouse.GetNumReplicateItems)
  if not integer(total) then
    if active then failure('The server response did not provide a valid listing count.',active) end
    return
  end
  if total==0 then
    local job=active or {total=0,index=0}; active=job
    failure('The server returned an empty full AH listing; complete coverage could not be confirmed.',job); return
  end
  local ownRequest=active~=nil
  local job={phase='reading',started=time(),seen=time(),market=market(),source=ownRequest and 'MobAuction' or 'Shared client full scan',
    total=total,index=0,items={},metadata={},requestedItems={},pending={},missing=0,itemCount=0,buyoutRows=0,bidOnly=0,own=0,sold=0,ownerUnknown=0}
  active=job; rememberRequest(); process(job)
end
function F.StartFullScan()
  if not F.db or not F.IsAuctionHouseOpen() then F.Say('Open the auction house first.'); return false end
  if active then F.Say('A full AH scan is already running. '..F.FullScanStatus()); return false end
  local api=C_AuctionHouse
  if not api or type(api.ReplicateItems)~='function' or type(api.GetReplicateItemInfo)~='function' or type(api.GetNumReplicateItems)~='function' then
    status('unavailable','This client does not expose full AH scanning.'); F.Say(F.fullScanState.message); return false
  end
  local last,requestSource=lastRequest(); local wait=last>0 and math.max(0,COOLDOWN-(time()-last)) or 0
  if wait>0 then
    local snapshot=F.db.fullScan
    local completed=type(snapshot)=='table' and snapshot.complete==true and snapshot.market==market() and
      snapshot.build==F.Build() and integer(snapshot.seen) and snapshot.seen>=last
    local message
    if completed then
      message=string.format('Full AH scan cooldown: about %d minutes remaining after a completed %s scan. Its snapshot prices remain available.',math.ceil(wait/60),requestSource or 'recent')
    else
      message=string.format('Full AH scan request cooldown: about %d minutes remaining. %s sent a request recently, but MobAuction has no completed current snapshot from it. WoW blocks another full request until the timer expires.',math.ceil(wait/60),requestSource or 'Another addon')
    end
    F.Say(message); return false
  end
  installHook()
  local job={phase='waiting',started=time(),market=market()}; active=job
  status('waiting','Requesting the full auction house snapshot. Keep the AH open.')
  local ok,err=pcall(api.ReplicateItems)
  if not ok then failure('The full AH scan request failed: '..tostring(err),job); return false end
  rememberRequest()
  schedule(TIMEOUT,function()
    if active==job then failure('No full AH response arrived within three minutes; the server may have refused the request.',job) end
  end)
  F.Say('Full AH scan requested. All item prices and recipe listings will be evaluated when the server response is complete.')
  refresh(); return true
end
function F.GetFullScanSnapshot()
  local snapshot=F.db and F.db.fullScan
  if type(snapshot)~='table' or snapshot.complete~=true or snapshot.market~=market() or snapshot.build~=F.Build() or type(snapshot.items)~='table' then return end
  local seen=snapshot.seen
  if not integer(seen) or time()<seen then return end
  -- Zero days requests a current quote: at most 60 seconds in the open AH.
  -- Positive day limits are exact durations, never rounded down by whole days.
  local maxAge=tonumber(F.db.maxAge) or 0
  local age=time()-seen
  if maxAge==0 then
    if age>60 or not F.IsAuctionHouseOpen() then return end
  elseif maxAge<0 or age>maxAge*86400 then return end
  return snapshot
end
function F.FullScanPrice(id)
  local snapshot=F.GetFullScanSnapshot()
  local row=snapshot and snapshot.items[id]
  if row and type(row.minUnit)=='number' and row.minUnit>0 then
    return row.minUnit,'Full AH snapshot', 'Snapshot minimum per item; whole stacks, ownership and current availability need checking.'
  end
end
function F.FullScanStatus()
  if active then return F.fullScanState and F.fullScanState.message or 'Full AH scan running.' end
  if F.fullScanState and F.fullScanState.phase~='complete' then return F.fullScanState.message end
  local snapshot=F.GetFullScanSnapshot()
  if snapshot then return string.format('Full AH snapshot: %d listings, %d item prices, %d minutes old. Snapshot prices are forecasts.',snapshot.total,snapshot.itemCount,math.floor((time()-snapshot.seen)/60)) end
  return 'No fresh complete AH snapshot. Open the AH and click Full scan.'
end
for _,event in ipairs({'REPLICATE_ITEM_LIST_UPDATE','AUCTION_HOUSE_CLOSED','PLAYER_INTERACTION_MANAGER_FRAME_HIDE','PLAYER_LOGIN','ADDON_LOADED'}) do events:RegisterEvent(event) end
events:SetScript('OnEvent',function(_,event,interaction)
  if event=='PLAYER_LOGIN' or event=='ADDON_LOADED' then installHook()
  elseif event=='REPLICATE_ITEM_LIST_UPDATE' then receive()
  elseif event=='AUCTION_HOUSE_CLOSED' or (Enum and Enum.PlayerInteractionType and interaction==Enum.PlayerInteractionType.Auctioneer) then
    F.CancelFullScan('Full AH scan cancelled because the auction house closed. Previous completed prices were kept.'); refresh()
  end
end)
