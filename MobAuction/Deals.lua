local _, F = ...
F.deals, F.dealNotified = {}, {}
local subclasses = { [1]=165, [2]=197, [3]=202, [4]=164, [5]=185, [6]=171, [7]=129, [8]=333, [9]=356, [10]=755, [11]=773 }
function F.CheckRecipeDeal(id, price)
  if not price or price <= 0 then return end
  local name, _, _, _, _, _, _, _, _, _, _, class, subclass = F.ItemInfo(id)
  if not name then F.ItemName(id); return end
  if class ~= 9 then return end -- Every recipe subclass, including future professions.
  local p = AHledgerAPI and F.Safe(AHledgerAPI.GetPrice, id)
  if not p or p.snapshot or not p.updated or time()-p.updated > F.db.maxAge*86400 or time() < p.updated then return end
  local reference = p.median7d or p.median30d
  if not reference or reference <= 0 then return end
  local saving, discount = reference-price, (1-price/reference)*100
  if saving < F.db.dealSaving or discount + 0.000001 < F.db.dealPercent then return end
  local profession = subclasses[subclass]
  local deal = { id=id, name=name, price=price, reference=reference, saving=saving, discount=discount,
    seen=time(), profession=profession, matches=profession and F.db.selectedProfessions[profession] or false }
  F.deals[id] = deal
  return deal
end
function F.ObserveRecipeDeals()
  if not F.db or not F.IsAuctionHouseOpen() then return end
  local results = C_AuctionHouse and F.Safe(C_AuctionHouse.GetBrowseResults) or {}
  local sent = 0
  for _, row in ipairs(results or {}) do
    local id = row.itemKey and row.itemKey.itemID
    if id then
      F.deals[id] = nil -- A refreshed listing can cease to be a bargain.
      -- Browse minima can include your own listing; don't call that a buyable deal.
      local deal = not row.containsOwnerItem and F.CheckRecipeDeal(id, row.minPrice)
      if F.db.dealAlerts and deal and sent < 3 and (not F.dealNotified[id] or time()-F.dealNotified[id] >= 1800) then
        F.Say(string.format('Recipe deal candidate: %s at %s (%.0f%% below historical asking price). /moba deals', deal.name, F.Money(deal.price), deal.discount))
        F.dealNotified[id] = time(); sent = sent+1
      end
    end
  end
end
function F.DealList()
  local list = {}
  if not F.IsAuctionHouseOpen() then return list end
  for _, deal in pairs(F.deals) do if time()-deal.seen <= 300 then list[#list+1]=deal end end
  table.sort(list, function(a,b) return a.saving > b.saving end)
  return list
end
local events = CreateFrame('Frame')
for _, event in ipairs({'AUCTION_HOUSE_BROWSE_RESULTS_UPDATED','AUCTION_HOUSE_BROWSE_RESULTS_ADDED','AUCTION_HOUSE_CLOSED','GET_ITEM_INFO_RECEIVED'}) do events:RegisterEvent(event) end
events:SetScript('OnEvent', function(_, event)
  if event == 'AUCTION_HOUSE_CLOSED' then F.deals = {}
  elseif F.db then F.ObserveRecipeDeals() end
end)
