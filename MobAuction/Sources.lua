local _, F = ...
local function safe(fn, ...)
  if type(fn) ~= 'function' then return nil end
  local ok, result = pcall(fn, ...)
  if ok then return result end
end
F.Safe = safe
function F.SetAuctionHouseOpen(open)
  open=open==true
  if not open or not F.ahOpen then
    -- Quotes and bargain candidates belong to one AH visit. Invalidate them
    -- even when a missed close event is discovered by checking the window.
    F.depth={}; F.depthRequests={}; F.deals={}; F.priceCache={}; F.depositQuotes={}
    if F.ClearAuctionLearning and F.ahOpen~=open then F.ClearAuctionLearning() end
  end
  F.ahOpen=open
end
function F.IsAuctionHouseOpen()
  -- Match Auctionator's public MultiSearch API. A missed SHOW event or a reload
  -- must not reject a window the player already has open; a hidden window must
  -- not keep authorizing requests because an old event flag is still true.
  local modern,legacy=AuctionHouseFrame,AuctionFrame
  local visible=safe(modern and modern.IsShown,modern)==true or safe(legacy and legacy.IsShown,legacy)==true
  F.SetAuctionHouseOpen(visible)
  return F.ahOpen==true
end
local auctionEvents=CreateFrame('Frame')
for _,event in ipairs({'AUCTION_HOUSE_SHOW','AUCTION_HOUSE_CLOSED','PLAYER_LOGIN','BAG_UPDATE_DELAYED',
    'PLAYER_INTERACTION_MANAGER_FRAME_SHOW','PLAYER_INTERACTION_MANAGER_FRAME_HIDE'}) do auctionEvents:RegisterEvent(event) end
auctionEvents:SetScript('OnEvent',function(_,event,interaction)
  if event=='AUCTION_HOUSE_SHOW' then F.SetAuctionHouseOpen(true)
  elseif event=='AUCTION_HOUSE_CLOSED' then F.SetAuctionHouseOpen(false)
  elseif event=='PLAYER_LOGIN' then F.IsAuctionHouseOpen()
  elseif event=='BAG_UPDATE_DELAYED' then
    -- A moved, sold or newly crafted output can change the ItemLocation used
    -- for a noncommodity quote. Retry visible forecasts after the bags settle.
    F.depositQuotes={}
    if F.window and F.window:IsShown() and F.Refresh then F.Refresh() end
    if F.details and F.details:IsShown() and F.RefreshDetails then F.RefreshDetails() end
  else
    local auctioneer=Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.Auctioneer
    if auctioneer and interaction==auctioneer then
      F.SetAuctionHouseOpen(event=='PLAYER_INTERACTION_MANAGER_FRAME_SHOW')
    end
  end
end)
function F.ItemInfo(id)
  if not id then return end
  local fn = C_Item and C_Item.GetItemInfo or GetItemInfo
  if fn then return fn(id) end
end
function F.ItemName(id)
  local name = F.ItemInfo(id)
  if not name and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
  return name
end
function F.MarketPrice(id)
  local snapshot=F.GetFullScanSnapshot and F.GetFullScanSnapshot()
  if snapshot then
    local price,source,warning=F.FullScanPrice(id)
    if price then return price,source,warning end
    return nil,'No purchasable listing in the full AH snapshot'
  end
  if F.priceCache and F.priceCache[id] then return unpack(F.priceCache[id]) end
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  local price = api and safe(api.GetAuctionPriceByItemID, 'MobAuction', id)
  local age = api and safe(api.GetAuctionAgeByItemID, 'MobAuction', id)
  local source, warning
  if price and price > 0 and age and age >= 0 and age <= F.db.maxAge then
    source = string.format('Auctionator (%gd old)', age)
  else
    local p = AHledgerAPI and safe(AHledgerAPI.GetPrice, id)
    if p and not p.snapshot and p.updated and time() - p.updated <= F.db.maxAge * 86400
        and time() >= p.updated and p.minBuyout and p.minBuyout > 0 then
      price, source = p.minBuyout, 'AHledger minimum'
      warning = 'AHledger market snapshot; verify current listings.'
    else
      return nil, 'No recent price'
    end
  end
  if F.priceCache then F.priceCache[id] = { price, source, warning } end
  return price, source, warning
end
function F.ForecastQuote(id, quantity, reagent)
  if not reagent then
    local name, _, _, _, _, _, _, _, _, _, _, _, _, bind = F.ItemInfo(id)
    if not name then F.ItemName(id); return nil, 'Loading output item data' end
    if bind == 1 or bind == 4 then return nil, 'Output cannot be auctioned' end
  end
  local vendor = reagent and F.db.vendors[id]
  if vendor and (time() - vendor.seen > 7 * 86400 or time() < vendor.seen) then vendor = nil end
  if reagent then
    local total, source, warning, evidence = F.BatchQuote(id, quantity, vendor)
    local book = F.depth[id]
    if F.IsAuctionHouseOpen() and book and time()>=book.seen and time()-book.seen <= 60 then return total, source, warning, evidence end
    local unit,marketSource,marketWarning=F.MarketPrice(id)
    if total~=nil and (not unit or total<=unit*quantity) then return total,source,warning,evidence end
    return unit and unit*quantity,marketSource,marketWarning or 'Forecast ingredient cost; check current quantities.',{kind='estimate'}
  end
  local unit, source, warning = F.MarketPrice(id)
  return unit and unit * quantity, source, warning or 'Sale price is a forecast, not a guaranteed sale.', { kind = 'estimate' }

end
function F.Quote(id,quantity,reagent)
  if reagent and F.db.strictCosts then
    local vendor=F.db.vendors[id]
    if vendor and (time()<vendor.seen or time()-vendor.seen>7*86400) then vendor=nil end
    return F.BatchQuote(id,quantity,vendor)
  end
  return F.ForecastQuote(id,quantity,reagent)
end
function F.ReadMerchant()
  for i = 1, safe(GetMerchantNumItems) or 0 do
    local price,bundle,available,purchasable,extended
    local info=C_MerchantFrame and safe(C_MerchantFrame.GetItemInfo,i)
    if info then
      price,bundle,available,purchasable,extended=info.price,info.stackCount,info.numAvailable,info.isPurchasable,info.hasExtendedCost
    elseif GetMerchantItemInfo then
      local ok,name,texture,usable
      ok,name,texture,price,bundle,available,purchasable,usable,extended=pcall(GetMerchantItemInfo,i)
      if not ok then price=nil end
    end
    local link = safe(GetMerchantItemLink,i)
    local id = safe(GetMerchantItemID,i) or (link and tonumber(link:match('item:(%d+)')))
    if id and available == -1 and not extended and purchasable ~= false and price and price > 0 and bundle and bundle > 0 then
      F.db.vendors[id] = { price = price, bundle = bundle, seen = time(), name = UnitName('npc') or 'supplier' }
    end
  end
end
local function validDeposit(amount)
  return type(amount)=='number' and amount>=0 and amount<math.huge and amount==math.floor(amount)
end
local function depositSource(kind,quantity,cached)
  local listing=kind=='commodity' and 'one commodity listing'
    or (quantity..' individual '..(quantity==1 and 'listing' or 'listings'))
  return 'Game quote ('..listing..(cached and '; cached this AH visit' or '')..')'
end
function F.Deposit(id, quantity, duration)
  if type(id)~='number' or id<=0 or id>=math.huge or id~=math.floor(id)
      or type(quantity)~='number' or quantity<1 or quantity>=math.huge or quantity~=math.floor(quantity)
      or type(duration)~='number' or duration<1 or duration>3 or duration~=math.floor(duration) then
    return nil,'Invalid item, listing quantity or duration'
  end
  if type(F.db.assumedDeposit)=='number' and F.db.assumedDeposit>=0 then
    return F.db.assumedDeposit*quantity,'Assumed deposit: '..F.Money(F.db.assumedDeposit)..' per output item'
  end
  local override = F.db.deposits[id] and F.db.deposits[id][duration]
  if validDeposit(override) then return override * quantity, 'Manual per-unit deposit' end
  local ah = C_AuctionHouse
  if not ah or not F.IsAuctionHouseOpen() then return nil, 'Open AH for a deposit quote' end
  -- Commodity quotes describe one exact batch. Noncommodity forecasts describe
  -- separate one-item listings, so only that listing's quote may be multiplied.
  -- Never reuse quotes across visits/builds, after bag changes, or after a minute.
  F.depositQuotes=F.depositQuotes or {}
  local record=F.depositQuotes[id]
  local quotes=record and record.durations[duration]
  local cached=quotes and quotes[record.kind=='item' and 1 or quantity]
  if cached and cached.build==F.Build() and time()>=cached.seen and time()-cached.seen<=60 then
    return cached.amount*(record.kind=='item' and quantity or 1),depositSource(record.kind,quantity,true)
  end
  local function remember(kind,amount)
    if not validDeposit(amount) then return end
    local row=F.depositQuotes[id]
    if not row or row.kind~=kind then row={kind=kind,durations={}}; F.depositQuotes[id]=row end
    row.durations[duration]=row.durations[duration] or {}
    row.durations[duration][kind=='item' and 1 or quantity]={amount=amount,seen=time(),build=F.Build()}
    return amount*(kind=='item' and quantity or 1),depositSource(kind,quantity,false)
  end
  -- These APIs accept a duration index and quantity, not a sale price. A
  -- commodity can be quoted by ID without owning it; an item needs a real bag
  -- location. Do not substitute Classic rates or a fabricated ItemLocation.
  local key = safe(ah.MakeItemKey, id)
  local info = key and safe(ah.GetItemKeyInfo, key)
  local triedCommodity=false
  if info and info.isCommodity == true then
    triedCommodity=true
    local amount = safe(ah.CalculateCommodityDeposit, id, duration, quantity)
    if validDeposit(amount) then return remember('commodity',amount) end
  end
  local container=C_Container or {}
  local numSlots=container.GetContainerNumSlots or GetContainerNumSlots
  local itemID=container.GetContainerItemID or GetContainerItemID
  local foundOutput=false
  if ItemLocation and ItemLocation.CreateFromBagAndSlot then
    for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
      for slot = 1, safe(numSlots,bag) or 0 do
        if safe(itemID,bag,slot) == id then
          foundOutput=true
          local location = safe(ItemLocation.CreateFromBagAndSlot,ItemLocation,bag,slot)
          local commodity = safe(ah.GetItemCommodityStatus, location)
          local statuses=Enum and Enum.ItemCommodityStatus
          if statuses and statuses.Commodity~=nil and commodity==statuses.Commodity then
            if not triedCommodity then
              triedCommodity=true
              local amount=safe(ah.CalculateCommodityDeposit,id,duration,quantity)
              if validDeposit(amount) then return remember('commodity',amount) end
            end
          elseif location and ((statuses and statuses.Item~=nil and commodity==statuses.Item)
              or (info and info.isCommodity==false)) then
            local amount = safe(ah.CalculateItemDeposit, location, duration, 1)
            if validDeposit(amount) then return remember('item',amount) end
          end
        end
      end
    end
  end
  if triedCommodity or foundOutput then return nil,'Game deposit data is loading or unavailable; refresh the quote.' end
  return nil,'Keep one crafted output in your bags at the AH to learn its deposit automatically.'
end
function F.ScanCraftPrices()
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  if not F.IsAuctionHouseOpen() then F.Say('Open the auction house first.'); return end
  if not api or not api.MultiSearchExact then F.Say('Enable Auctionator to scan. AHledger prices can still be used with Refresh.'); return end
  F.DiscoverProfessions(); F.ReadRecipes()
  local ids, terms, names, missing = {}, {}, {}, 0
  for _, recipe in pairs(F.db.recipes) do
    if F.ScanEligible(recipe) then
      ids[recipe.output] = true
      for _, reagent in ipairs(recipe.reagents) do ids[reagent.itemID] = true end
    end
  end
  for id in pairs(ids) do
    local name = F.ItemName(id)
    if not name then missing = missing + 1
    elseif not names[name] then terms[#terms + 1] = name; names[name] = true end
  end
  if missing > 0 then F.Say('Loading ' .. missing .. ' item names. Click Scan again in a moment.'); return end
  if #terms == 0 then F.Say(F.ScanStatus()); return end
  table.sort(terms)
  local ok, err = pcall(api.MultiSearchExact, 'MobAuction', terms)
  if ok then
    F.Say('Searching ' .. #terms .. ' items. Then open /moba and click a recipe to Check its reagent quantities. Browse prices alone are estimates.')
    if F.window then F.window:Hide() end
  else F.Say('Search could not start: ' .. tostring(err)) end
end
function F.Scan()
  if F.StartFullScan then return F.StartFullScan() end
  F.Say('Full AH scanning is unavailable in this loaded version. Using targeted price searches.')
  return F.ScanCraftPrices()
end
function F.OnFullScanComplete(snapshot)
  F.priceCache={}; F.depth={}; F.depthRequests={}
  if F.ObserveFullScanRecipes then F.ObserveFullScanRecipes(snapshot) end
  if F.Refresh then F.Refresh() end
  if F.RefreshDetails then F.RefreshDetails() end
end
