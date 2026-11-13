local _, F = ...
-- Identifiers seed the search; locations, levels and rates are read from enabled
-- providers at runtime. No Classic loot table is shipped as Forever truth.
local seeds={2589,2592,4306,4338,14047,2318,2319,4234,4304,8170,
  2770,2771,2772,3858,10620,2835,2836,2838,7912,12365,
  2447,765,2449,785,2450,2452,2453,3355,3356,3357,3358,3818,3819,
  3820,3821,4625,8831,8838,8839,8845,8846,13463,13464,13465,13466,13467,
  769,730,731,723,729,1080,1015,12037,12202,12203,12204,12205,12208,
  5465,5466,5467,5468,5469,5470,5471,6889,5503,5504,
  7067,7068,7069,7070,7075,7076,7077,7078,7079,7080,7081,7082,7972}
local function module(name)
  return QuestieLoader and F.Safe(QuestieLoader.ImportModule,QuestieLoader,name)
end
function F.FarmProviders()
  local db=LibQuestieDB
  if not db or not db.Item or not db.Npc or not db.Object
      or F.Safe(db.RequireContract,4)~=true then
    return nil,'Enable a compatible QuestieDB and Questie for farming locations and reference rates.'
  end
  local zones=module('ZoneDB')
  if not zones or not zones.GetUiMapIdByAreaId then
    return nil,'Enable Questie alongside QuestieDB, then reload, for farming locations.'
  end
  return {db=db,zones=zones,drops=module('QuestieDB')}
end
function F.FarmCandidates()
  local ids={}
  for _,id in ipairs(seeds) do ids[id]=true end
  for _,recipe in pairs(F.db.recipes) do
    if recipe.observedBuild==F.Build() then
      for _,reagent in ipairs(recipe.reagents or {}) do ids[reagent.itemID]=true end
    end
  end
  local list={}; for id in pairs(ids) do list[#list+1]=id end
  table.sort(list); return list
end
local function places(provider,spawns)
  local result={}
  provider.zoneCache=provider.zoneCache or {}
  for area,coords in pairs(type(spawns)=='table' and spawns or {}) do
    local cached=provider.zoneCache[area]
    if cached==nil then
      local map=F.Safe(provider.zones.GetUiMapIdByAreaId,provider.zones,area)
      local info=map and C_Map and F.Safe(C_Map.GetMapInfo,map)
      local dungeon=F.Safe(provider.zones.IsDungeonZone,area)
      cached=info and info.name and info.mapType==((Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3) and dungeon==false and {map=map,info=info} or false
      provider.zoneCache[area]=cached
    end
    -- Require an identified outdoor zone, and reject known dungeons even if a
    -- provider maps their entrance to an outdoor map.
    if cached then
      local map,info=cached.map,cached.info
      local samples={}
      for _,point in ipairs(type(coords)=='table' and coords or {}) do
        local x,y=type(point)=='table' and point[1],type(point)=='table' and point[2]
        if type(x)=='number' and type(y)=='number' and x>=0 and x<=100 and y>=0 and y<=100 then
          samples[#samples+1]=string.format('%.1f, %.1f',x,y)
          if #samples==3 then break end
        end
      end
      if #samples>0 then result[#result+1]={zone=info.name,map=map,coords=table.concat(samples,' / ')} end
    end
  end
  table.sort(result,function(a,b) return a.zone<b.zone end)
  return result
end
local function sourceLess(a,b)
  if (a.rate~=nil)~=(b.rate~=nil) then return a.rate~=nil end
  if a.rate~=b.rate then return (a.rate or -1)>(b.rate or -1) end
  if a.level~=b.level then return (a.level or math.huge)<(b.level or math.huge) end
  return a.id<b.id
end
function F.FarmSources(itemID,provider)
  local db=provider.db; local result={}
  local faction=F.Safe(UnitFactionGroup,'player')
  local factionKey=faction=='Alliance' and 'A' or (faction=='Horde' and 'H')
  local npcs=F.Safe(db.Item.npcDrops,itemID)
  for _,id in ipairs(type(npcs)=='table' and npcs or {}) do
    local friendly=F.Safe(db.Npc.friendlyToFaction,id)
    local level=F.Safe(db.Npc.maxLevel,id)
    if factionKey and friendly~='AH' and friendly~=factionKey and F.Safe(db.Npc.rank,id)==0
        and type(level)=='number' and level>=1 then
      local locations=places(provider,F.Safe(db.Npc.spawns,id))
      if #locations>0 then
        local data=provider.drops and F.Safe(provider.drops.GetItemDroprate,itemID,id)
        local rate=type(data)=='table' and data[1] or nil
        if type(rate)~='number' or rate~=rate or rate<0 or rate>100 then rate=nil end
        -- Zero is an explicit no-drop reference, not a missing percentage.
        if rate~=0 then result[#result+1]={id=id,kind='npc',name=F.Safe(db.Npc.name,id) or ('NPC '..id),
          level=level,minLevel=F.Safe(db.Npc.minLevel,id),places=locations,rate=rate,
          rateSource=rate and tostring(data[2] or 'Questie') or nil} end
      end
    end
  end
  local objects=F.Safe(db.Item.objectDrops,itemID)
  for _,id in ipairs(type(objects)=='table' and objects or {}) do
    local locations=places(provider,F.Safe(db.Object.spawns,id))
    if #locations>0 then result[#result+1]={id=id,kind='object',name=F.Safe(db.Object.name,id) or ('Object '..id),places=locations} end
  end
  table.sort(result,sourceLess); return result
end
function F.FarmLevel()
  return F.farmLevel or F.Safe(UnitLevel,'player') or 0
end
function F.FarmResults()
  local provider,err=F.FarmProviders()
  local stats={unpriced=0,above=0,unmapped=0,loading=0}
  if not provider then return {},err,stats end
  local results={}; F.priceCache={}
  for _,id in ipairs(F.FarmCandidates()) do
    local sources=F.FarmSources(id,provider)
    local best
    for _,source in ipairs(sources) do
      if F.farmAllLevels or (source.level and source.level<=F.FarmLevel()) then best=source; break end
    end
    if #sources==0 then stats.unmapped=stats.unmapped+1
    elseif not best then stats.above=stats.above+1
    else
      local name,_,_,_,_,_,_,_,_,_,_,class,_,bind=F.ItemInfo(id)
      -- Require cached item data before suggesting sale; quest/bound items cannot qualify.
      if not name then F.ItemName(id); stats.loading=stats.loading+1
      elseif bind~=1 and bind~=4 and class~=12 then
        local price,priceSource=F.MarketPrice(id)
        if not price then stats.unpriced=stats.unpriced+1
        else
          local net=price-math.ceil(price*F.db.cut/100)
          if net>0 then
            -- Reference model only: one item per successful drop, 100 kills,
            -- after AH cut and before deposit/relist and travel costs.
            results[#results+1]={id=id,name=name,price=price,net=net,priceSource=priceSource,
              sources=sources,best=best,level=best.level,score=best.rate and net*best.rate}
          end
        end
      end
    end
  end
  table.sort(results,function(a,b)
    if (a.score~=nil)~=(b.score~=nil) then return a.score~=nil end
    if a.score~=b.score then return (a.score or -1)>(b.score or -1) end
    if a.net~=b.net then return a.net>b.net end
    return a.id<b.id
  end)
  return results,nil,stats
end
function F.ScanFarms()
  if not F.IsAuctionHouseOpen() then F.Say('Open the auction house first.'); return end
  local api=Auctionator and Auctionator.API and Auctionator.API.v1
  if not api or not api.MultiSearchExact then F.Say('Enable Auctionator to scan farm prices.'); return end
  local provider,err=F.FarmProviders(); if not provider then F.Say(err); return end
  local terms,names,missing={},{},0
  for _,id in ipairs(F.FarmCandidates()) do
    local sources=F.FarmSources(id,provider); local eligible=false
    for _,source in ipairs(sources) do
      if F.farmAllLevels or (source.level and source.level<=F.FarmLevel()) then eligible=true; break end
    end
    if eligible then
      local name,_,_,_,_,_,_,_,_,_,_,class,_,bind=F.ItemInfo(id)
      if not name then F.ItemName(id); missing=missing+1
      elseif bind~=1 and bind~=4 and class~=12 and not names[name] then terms[#terms+1]=name; names[name]=true end
    end
  end
  if missing>0 then F.Say('Loading farm item names. Click Scan farm prices again in a moment.'); return end
  if #terms==0 then F.Say('No mapped farm sources at this level. Try All levels or refresh after Questie has initialized.'); return end
  table.sort(terms)
  local ok,why=pcall(api.MultiSearchExact,'MobAuction',terms)
  if ok then
    F.Say('Scanning '..#terms..' farm items. Let Auctionator finish, then return to /moba farms and Refresh.')
    if F.window then F.window:Hide() end
  else F.Say('Search could not start: '..tostring(why)) end
end
