local _, F = ...
F.depth = {}
-- Exact bounded purchase cost. Commodities are divisible; item auctions are whole lots.
function F.DepthCost(book, quantity, vendor, work)
  local best, plan
  local vendorCost = vendor and math.ceil(quantity / vendor.bundle) * vendor.price
  if vendorCost then best, plan = vendorCost, 'Vendor' end
  if not book or not book.complete then return best, plan end
  if work then
    local needed=#book.lots*(book.kind=='item' and quantity or (2+math.ceil(math.log(#book.lots+1)/math.log(2))))
    if needed>work.remaining then work.limited=true; return nil,nil,'Batch planning work limit' end
    work.remaining=work.remaining-needed
  end
  if book.kind == 'commodity' then
    local units,costs,totalUnits,totalCost={},{},0,0
    for i,lot in ipairs(book.lots) do
      totalUnits=totalUnits+lot.quantity; totalCost=totalCost+lot.quantity*lot.price
      units[i],costs[i]=totalUnits,totalCost
    end
    local function prefix(wanted)
      if wanted==0 then return 0 end
      if wanted>totalUnits then return end
      local low,high=1,#units
      while low<high do
        local middle=math.floor((low+high)/2)
        if units[middle]>=wanted then high=middle else low=middle+1 end
      end
      return (costs[low-1] or 0)+(wanted-(units[low-1] or 0))*book.lots[low].price
    end
    local candidates = { [0] = true }
    if vendor then
      candidates[math.ceil(quantity / vendor.bundle)] = true
      local cumulative = 0
      for _, lot in ipairs(book.lots) do
        cumulative = cumulative + lot.quantity
        local boundary = (quantity - cumulative) / vendor.bundle
        candidates[math.max(0, math.floor(boundary))] = true
        candidates[math.max(0, math.ceil(boundary))] = true
      end
    end
    for bundles in pairs(candidates) do
      local needed = math.max(0, quantity - bundles * (vendor and vendor.bundle or 0))
      local cost = prefix(needed)
      if cost then
        cost = cost + bundles * (vendor and vendor.price or 0)
        if best == nil or cost < best then best, plan = cost, bundles > 0 and 'AH + vendor' or 'AH depth' end
      end
    end
  else
    -- Cap work rather than freeze the client on huge whole-stack purchase problems.
    if quantity > 1000 or #book.lots > 500 then return vendorCost, vendorCost and 'Vendor' or nil, 'Whole-stack calculation limit' end
    local costs = { [0] = 0 }
    for _, lot in ipairs(book.lots) do
      for count = quantity - 1, 0, -1 do
        if costs[count] then
          local nextCount = math.min(quantity, count + lot.quantity)
          local price = costs[count] + lot.price
          if not costs[nextCount] or price < costs[nextCount] then costs[nextCount] = price end
        end
      end
    end
    for count, cost in pairs(costs) do
      if count == quantity or vendor then
        local total = cost + (vendor and math.ceil((quantity - count) / vendor.bundle) * vendor.price or 0)
        if best == nil or total < best then best, plan = total, count < quantity and 'AH + vendor' or 'AH whole stacks' end
      end
    end
  end
  return best, plan
end
function F.CaptureDepth(kind, ref)
  if not F.IsAuctionHouseOpen() or not C_AuctionHouse then return end
  local ah, id = C_AuctionHouse, kind == 'commodity' and ref or ref.itemID
  -- Only the exact item query we requested is eligible for whole-item pricing.
  if kind == 'item' then
    local wanted = F.depthRequests and F.depthRequests[id]
    if not wanted then return end
    for _, field in ipairs({'itemID', 'itemLevel', 'itemSuffix', 'battlePetSpeciesID'}) do
      if (wanted[field] or 0) ~= (ref[field] or 0) then return end
    end
  end
  local fullFn = kind == 'commodity' and ah.HasFullCommoditySearchResults or ah.HasFullItemSearchResults
  local countFn = kind == 'commodity' and ah.GetNumCommoditySearchResults or ah.GetNumItemSearchResults
  local rowFn = kind == 'commodity' and ah.GetCommoditySearchResultInfo or ah.GetItemSearchResultInfo
  local book = { kind = kind, lots = {}, seen = time(), complete = F.Safe(fullFn, ref) == true }
  local count = F.Safe(countFn, ref)
  if not count then book.complete = false end
  local seen = {}
  for i = 1, count or 0 do
    local row = F.Safe(rowFn, ref, i)
    if not row then book.complete = false
    elseif not row.containsOwnerItem and not row.containsAccountItem then
      local price = kind == 'commodity' and row.unitPrice or row.buyoutAmount
      if price and price > 0 and row.quantity and row.quantity > 0 then
        if kind == 'commodity' or not row.auctionID or not seen[row.auctionID] then
          book.lots[#book.lots + 1] = { price = price, quantity = row.quantity }
          if row.auctionID then seen[row.auctionID] = true end
        end
      end
    end
  end
  table.sort(book.lots, function(a,b) return a.price / (kind == 'item' and a.quantity or 1) < b.price / (kind == 'item' and b.quantity or 1) end)
  F.depth[id] = book
end
function F.RequestDepth(id)
  if not F.IsAuctionHouseOpen() then F.Say('Open the auction house first.'); return end
  local ah = C_AuctionHouse
  if not ah or not ah.SendSearchQuery then F.Say('Detailed auction searches unavailable.'); return end
  if ah.IsThrottledMessageSystemReady and not ah.IsThrottledMessageSystemReady() then F.Say('Auction house busy; try again shortly.'); return end
  local key = F.Safe(ah.MakeItemKey, id)
  if not key or not F.Safe(ah.GetItemKeyInfo, key) then F.ItemName(id); F.Say('Item data loading; try Check again.'); return end
  local previous = F.depth[id]
  if previous and not previous.complete and previous.kind and time()>=previous.seen and time()-previous.seen<=60 then
    local more = previous.kind == 'commodity' and ah.RequestMoreCommoditySearchResults or ah.RequestMoreItemSearchResults
    if more then
      local ok = pcall(more, previous.kind == 'commodity' and id or key)
      if not ok then F.depth[id]=nil; F.Say('Could not request more results; click Check to start a fresh search.') end
      return
    end
  end
  F.depth[id] = { complete = false, seen = time(), lots = {} }
  F.depthRequests = F.depthRequests or {}; F.depthRequests[id] = key
  local ok, err = pcall(ah.SendSearchQuery, key, {}, false)
  if not ok then F.depth[id]=nil; F.Say('Search failed: ' .. tostring(err)) end
end
function F.BatchQuote(id, quantity, vendor)
  local open=F.IsAuctionHouseOpen()
  local book = F.depth[id]
  if not open or not book or time() - book.seen > 60 or time() < book.seen then
    local cost, plan = F.DepthCost(nil, quantity, vendor)
    if cost then return cost, plan .. ': ' .. vendor.name, 'Supplier observation; verify current discounts.', { kind = 'vendor' } end
    return nil, 'Check current listings', 'No fresh quantity data', { kind = 'missing' }
  end
  local cost, plan, limit = F.DepthCost(book, quantity, vendor, F.planningWork)
  if cost then return cost, plan, 'Observed listing prices can change before purchase.', { kind = 'depth', age = time() - book.seen } end
  return nil, limit or (book.complete and 'Insufficient purchasable stock' or 'Incomplete search results'), nil, { kind = 'missing' }
end
local events = CreateFrame('Frame')
for _, event in ipairs({'COMMODITY_SEARCH_RESULTS_UPDATED', 'COMMODITY_SEARCH_RESULTS_ADDED', 'ITEM_SEARCH_RESULTS_UPDATED',
  'ITEM_SEARCH_RESULTS_ADDED', 'COMMODITY_PURCHASE_SUCCEEDED', 'AUCTION_HOUSE_AUCTION_CREATED', 'AUCTION_CANCELED',
  'AUCTION_HOUSE_SHOW', 'AUCTION_HOUSE_CLOSED', 'AUCTION_HOUSE_PURCHASE_COMPLETED'}) do events:RegisterEvent(event) end
events:SetScript('OnEvent', function(_, event, ref)
  if event:find('COMMODITY_SEARCH_RESULTS') then F.CaptureDepth('commodity', ref)
  elseif event:find('ITEM_SEARCH_RESULTS') and type(ref) == 'table' then F.CaptureDepth('item', ref)
  else F.depth = {}; F.depthRequests = {} end
  if F.RefreshDetails then F.RefreshDetails() end
end)
