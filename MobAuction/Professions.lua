local _, F = ...
F.professions = { [129]='First Aid', [164]='Blacksmithing', [165]='Leatherworking', [171]='Alchemy',
  [182]='Herbalism', [185]='Cooking', [186]='Mining', [197]='Tailoring', [202]='Engineering',
  [333]='Enchanting', [356]='Fishing', [393]='Skinning' }
F.gathering = { [182]=true, [356]=true, [393]=true }
function F.RecipeTerm(profession, plural)
  if profession==164 then return plural and 'plans' or 'plan' end
  return plural and 'recipes' or 'recipe'
end
function F.ProfessionIDByName(name)
  if type(name)~='string' or name=='' then return end
  for id,known in pairs(F.professions) do
    if type(id)=='number' and id>0 and (known==name or F.db.professionNames[id]==name) then return id end
  end
end
function F.ProfessionIDFromInfo(info)
  if type(info)~='table' then return end
  local function valid(id) return type(id)=='number' and id>0 and id==math.floor(id) end
  -- Expansion skill lines belong to their base profession in the character filter.
  if valid(info.parentProfessionID) then return info.parentProfessionID end
  if valid(info.professionID) then return info.professionID end
  if valid(info.skillLineID) then return info.skillLineID end
  return F.ProfessionIDByName(info.professionName)
end
function F.ProfessionIDs()
  local ids = {}; for id in pairs(F.professions) do ids[#ids+1]=id end
  table.sort(ids, function(a,b) return F.professions[a] < F.professions[b] end)
  return ids
end
function F.DiscoverProfessions()
  local found, complete = {}, false
  local function remember(id,name,rank)
    if type(id)=='number' and id>0 and type(name)=='string' and name~='' and type(rank)=='number' and rank>0 then
      F.professions[id]=name; F.db.professionNames[id]=name
      F.db.detectedSkills[id]=rank; found[id]=rank
    end
  end
  if GetProfessions and GetProfessionInfo then
    local values={pcall(GetProfessions)}
    if values[1] then
      complete=true
      for k,index in pairs(values) do if k>1 then
        local ok,name,_,rank,_,_,_,id=pcall(GetProfessionInfo,index)
        if ok then remember(id,name,rank) else complete=false end
      end end
    end
  end
  -- Forever exposes the Skills pane through C_SkillInfo. Legacy clients use
  -- the global equivalents. Collapsed headers make this a partial census.
  if not next(found) then
    complete=false
    local api=C_SkillInfo
    if api and api.GetSkillLineInfoByID then
      for id in pairs(F.professions) do
        local row=F.Safe(api.GetSkillLineInfoByID,id)
        if row and not row.isHeader then remember(id,row.name,row.rank) end
      end
      if next(found) then complete=true end
    end
    local count=not next(found) and F.Safe(api and api.GetNumSkillLines or GetNumSkillLines)
    if type(count)=='number' and count>0 then
      complete=true
      for i=1,count do
        if api and api.GetSkillLineInfo then
          local row=F.Safe(api.GetSkillLineInfo,i)
          if not row then complete=false
          elseif row.isHeader then if row.isCollapsed then complete=false end
          else
            local id=F.professions[row.skillID] and row.skillID or F.ProfessionIDByName(row.name)
            remember(id,row.name,row.rank)
          end
        elseif GetSkillLineInfo then
          local ok,name,header,expanded,rank=pcall(GetSkillLineInfo,i)
          if not ok then complete=false
          elseif header then if not expanded then complete=false end
          else remember(F.ProfessionIDByName(name),name,rank) end
        end
      end
    end
  end
  F.currentProfessionsComplete=complete
  if complete then F.currentProfessions=found
  elseif next(found) then
    F.currentProfessions=F.currentProfessions or {}
    for id,rank in pairs(found) do F.currentProfessions[id]=rank end
  end
  return found
end
function F.SaveSetup(selected, levels)
  local count = 0
  for id, enabled in pairs(selected) do
    if enabled then
      count = count+1
      if not F.professions[id] then return false, 'Unknown profession.' end
      local value = levels[id] or ''
      local n = tonumber(value)
      if value ~= '' and (not n or n < 0 or n > 1000 or n ~= math.floor(n)) then
        return false, 'Skill levels must be whole numbers from 0 to 1000.'
      end
    end
  end
  if count == 0 then return false, 'Select at least one profession.' end
  F.db.selectedProfessions = {}
  for id, enabled in pairs(selected) do
    if enabled then
      F.db.selectedProfessions[id] = true
      -- Accepting a detected rank should keep following future skill gains.
      local value=levels[id] or ''
      F.SetSkill(id,tonumber(value)==F.db.detectedSkills[id] and 'auto' or value)
    end
  end
  F.db.setupComplete = true; F.filter = nil; F.page = 1
  return true
end
