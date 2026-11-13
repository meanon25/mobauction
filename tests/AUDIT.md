# 0.6.0 release audit

Implemented a server-wide AH snapshot, independent of recipe imports. Scan results commit atomically, exclude own/sold/bid-only rows, preserve previous data on failures, track the shared cooldown, and use instant item classification when full item cache data is unavailable. Metadata waits are bounded and chunked. Fresh complete snapshots prevent older addon prices from filling absent listings; detailed quantity checks remain separate.

Added a reference catalogue with bounded automatic discovery and optional Recipe Registry Forever integration. Database records are unverified research, with explicit source build and unknown learned status. Current client identity, owner and schematic evidence supersedes reference data. Only verified character knowledge can add a reference recipe to Crafting. Registry data is read from its installed addon; no complete external recipe database was bundled or installed here.

Worth Learning includes catalogue research or an AH-only filter, uses one craft, sorts by Sale profit, and keeps recipe/trainer cost separate. UI tests cover reference pagination, unknown learning labels, old-import precedence, and detail navigation. Assumed deposit remains 1 silver per output item.

Validation: 1,070 mocked checks passed before final packaging; Lua and installer syntax and fresh/update installs are checked separately. These tests do not operate WoW or establish live server/API behavior. The 0.6 checklist in IN_GAME.md remains to be run in game.

The historical audits below describe their release at the time.

# MobAuction usability and correctness audit

Reviewed 2026-11-11 and 2026-11-12. This report covers the workspace build, not a claim of live-client certification.

## 0.5.1: scan workflow follow-up

The user reported missing learning opportunities, unexpected Sale profit order and no scrolling, with Savory Stag Sliders as a concrete example. Normal Crafting already sorted by sale profit, while Worth Learning sorted by adjusted profit; both now use Sale profit. The existing page controls gained mouse-wheel handling over the panel and rows. Learning now shows ingredient forecasts and unresolved recipe items explicitly; checked stock remains necessary for strong flags. Recipe browsing automatically continues pages with throttling, query ownership, close cancellation and a bounded waiting period.

The requested 1s/output deposit assumption is labeled and can be switched to game quotes. Upgrade enables scan forecasts once instead of requiring manual quantity checks before displaying any profit. Existing game-quote and strict-cost regression fixtures explicitly select those modes. The full suite passes 753 mocked checks, including the actual saved Sliders reagent quantities, supplier bundles, unknown spice cost, scroll boundaries, assumed deposits, forecast labeling, and automatic recipe paging.

## 0.5.0: automatic imports, profit ordering and auction recipes

Profession open/source events now import immediately and coalesce delayed retries while identities or ingredients load. Retries stop after six delayed attempts, cancel on close or source changes, and can recover on subsequent real data events. The existing ownership and stable-source checks remain in force. A partial legacy reagent read now records a partial state so late item data can complete it. Visible opportunities and details update after automatic imports. The latest persisted user data still had no verified Blacksmithing/Cooking imports; only live-client validation can establish that the new timing behavior resolves that session's failure.

Crafting order now follows the displayed Sale profit, descending, independent of estimated material costs and failed-listing deposits. Missing profits sort last. Worth Learning compares one craft at a time and ranks by profit after expected failed deposits. Recipe purchase and trainer prices appear in a separate Learn price column and do not enter profit, ranking or flag calculations, following the user's explicit instruction. List/detail quantities and navigation are covered by UI contract tests.

Automatic deposit quotes use the game's ID-based commodity API or an actual bag location for noncommodities. The cache is scoped to the current AH visit, build, duration and commodity quantity; individual item listings reuse only their quoted one-item amount. Bag changes and AH transitions invalidate it. Invalid responses remain unknown, actual zero is preserved, and missing responses are not cached. A noncommodity output still needs to be in bags; no unsupported vendor-price formula is substituted.

Auction learning research is a user-initiated class-9 browse query. Candidate item spell IDs must validate against an actual recipe, profession and supported schematic; names are not used for mapping. Usability and actual detected skills gate learning flags. Own/account listings and stale prices are excluded. Checked material costs, output sale prices and deposits determine one-craft profitability. A strong learning flag also requires fresh AHledger estimated demand; neither an asking price nor estimated demand guarantees a sale. Unknown mappings and incomplete costs remain visible as diagnostics or pending candidates.

The full suite passes **723 mocked checks**. Lua and installer syntax checks pass. The new API/UI timing, mappings on actual Forever recipe items, deposits against the posting panel, and rendering remain on the [live acceptance checklist](IN_GAME.md). Automated checks are mocked contracts, not live certification.

## 0.4.4: Auction house open detection

The installed 0.4.3 code authorized every AH operation using `F.ahOpen`, updated only by older `AUCTION_HOUSE_SHOW/CLOSED` events in the recipe importer. The installed Auctionator modern backend initializes and updates through `PLAYER_INTERACTION_MANAGER_FRAME_SHOW/HIDE` with `Enum.PlayerInteractionType.Auctioneer`. Its public MultiSearch API requires a shown `AuctionHouseFrame` or `AuctionFrame`. MobAuction could therefore reject the same open window Auctionator accepts.

AH lifecycle tracking now lives in Sources, independently of recipe importing. All AH consumers use one visible-window check. Modern and legacy events maintain state, while direct checks recover from missed show/close events. No visible AH frame means no request, even if an old flag says open. Depth, pending item requests, bargains and price caches are invalidated on closure and entry into a new visit; the depth lookup happens after validation to avoid retaining an old local book reference. Opening or closing the AH does not initiate scans.

The full mocked suite passes **503 checks**, including 51 new assertions for direct crafting/farm searches, deposits, detailed listing requests/capture, modern and legacy windows, missing frames, unrelated interaction events, Auctioneer transitions and stale quote/deal rejection. Live timing and rendering still require an in-game check.

## 0.4.3: Blacksmithing follow-up

The installed Forever manifest is 0.4.2. The saved catalogue still contained 135 records labelled Fishing, with no Blacksmithing records. That persisted file retained old observation fields; this does not prove the running client version, because a reload can save the old state immediately before loading updated code. No MobAuction error appeared in the persisted BugGrabber log. A fresh in-game import result is still needed to establish the exact runtime failure.

The status mixed a global catalogue count with a selected-profession eligible count. It now leads with the selected profession's saved and eligible counts, shows the global total separately, and scopes exclusion reasons to the selection. Blacksmithing uses plan/plans in status, the first column, detail IDs, catalogue titles and pagination; all-profession views retain generic recipe wording.

The Forever client helper `Professions.GetProfessionInfo()` selects child profession info before falling back to base info. Its list-update handler checks `IsDataSourceChanging()`. The importer previously used only the base context and tracked changing events without reading API readiness. Compatibility work follows the client's selection/readiness behavior, preserves source identity checks, allows other validated entries to load while one entry's identity is unavailable, and records the loaded addon version plus the latest active import attempt.

The full suite passes **452 checks**, including selected-child/base disagreement, ready/changing API answers, partial identity/info/ingredient loading, complete-record preservation, bounded saved diagnostics, source-counter/raw-child changes, selected-profession counts, plan wording and manual Refresh feedback. Lua and installer syntax checks pass. A read-only replay of the latest saved file confirms the new status identifies 0 Blacksmithing plans and separately flags the 135 older entries for repair.

References: [Forever profession selection helper](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_ProfessionsTemplates/Blizzard_Professions.lua), [Forever profession window](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_Professions/Blizzard_ProfessionsFrame.lua). The acceptance checklist remains necessary for actual client timing and display.

## 0.4.2: Cooking import follow-up

After 0.4.1 was installed, a newer saved file contained 135 Cooking recipe records labelled Fishing (356), including Charred Wolf Meat (2538) and Roasted Boar Meat (2540). Learned observations carried Fishing rank 1. The saved manual Cooking rank was 225 while the detected rank was 244. These are concrete explanations for an empty Cooking filter; the saved file does not establish the exact order of game/API events that produced them.

Modern imports now check each recipe's profession against the active source, stage records until the source ID and counter remain stable, and take the snapshot before skill discovery. Refresh and AH scans do not read closed profession windows. Incomplete data preserves prior records, and trainer/earliest-rank evidence cannot cross profession boundaries. Source-changing events defer imports; details-ready events retry them. Clients without a recipe-specific API need an independently named, visible legacy profession window.

Older modern imports are marked for reimport without deleting the catalogue or character settings. Empty states and Catalogue explain the repair even when wrongly labelled records fall outside the Cooking filter. Invalid empty profession 0 is removed. Main/setup screens expose manual and detected ranks, with a Use detected levels action limited to selected professions detected now.

`tests/import_regression.lua` replays Cooking/Blacksmithing switching, a Fishing source with stale Cooking IDs, missing data, a mid-read source change, migration, cross-profession evidence contamination, and saved imports used with profession windows closed. The full mocked suite passes **365 checks**, including detected-level buttons and discovery changing the active context. Lua syntax and ZIP/source integrity checks pass. Live event timing and rendering still need confirmation; if the client persistently reports conflicting identities and offers no legacy reader, imports stop with a diagnostic instead of guessing.

The following sections record the earlier 0.4.1 audit.

## Evidence and scope

The installed addon manifest was 0.4.0. The saved per-character MobAuction file contained no recipes or detected ranks; saved files can lag an active session. No MobAuction/ForgeProfit entries were found in the persisted BugGrabber log. The importer only supported modern schematics, whereas the installed Auctionator/AHledger also read legacy TradeSkill/Craft windows. That missing reader was a concrete compatibility gap; the saved file alone cannot prove which path the running character used.

Reviewed every active Lua module, startup/load order, slash commands, optional dependencies, pricing assumptions and installation script. Checked modern API fields against the Forever documentation and connector calls against installed Auctionator/AHledger/Questie code. Expanded the mocked event/UI suite to exercise user flows rather than only individual calculations.

## Fixed and tested

| Area | Finding | Result |
| --- | --- | --- |
| Window navigation | Catalogue/detail windows could share space with the underlying page | One visible MobAuction page; Back/X/Escape return to the previous page; launcher returns to main |
| Catalogue | Inspecting a recipe required typing an ID command | Clickable recipe rows, twenty per page, scroll reset and plain-language exclusion reasons |
| Recipe import | No legacy TradeSkill/Craft reader | Imports visible learned recipes, correct reagent counts, minimum output yield and stable identity; handles late links and rejects linked/non-item outputs |
| Profession detection | Only retail-style profession globals | Forever skill-by-ID and skill-list discovery, legacy fallback, no false unlearning from collapsed headers |
| Skill setup | Saving a detected number froze it as a manual override | Accepting the detected rank follows future skill gains; a different number still previews a lower/higher rank |
| Price scan | Empty import and filtering errors shared a vague message | Specific import/filter/build/rank/unsupported-data messages; read the open profession before searching |
| Research prices | Unlearned recipes could not get scanned through the normal flow | Catalogue price searches can include unlearned/unknown-minimum recipes without granting craft eligibility |
| Supplier costs | Missing modern merchant reader and incorrect legacy field offsets | Correct purchasable/usable/extended-cost handling; only unlimited gold purchases qualify; whole bundles retained |
| Profit display | Missing output/deposit evidence could hide known material costs or appear fully checked | Material costs remain visible; deposit gaps have a distinct state; Refresh clears sale-price cache |
| Fees | Assumptions required slash commands to edit | Fees & settings with atomic validation; cut is explicit and not inferred from AH type |
| Partial AH searches | Expired partial queries kept requesting more old results | Start fresh after expiry; failed requests clear pending state |
| Recipe deals | Muting chat froze the candidate list; own minima could look buyable | Silent collection continues while muted; own browse minima excluded |
| Learning recommendations | Legacy-only catalogues could leave an unexplained empty view | Explicit explanation of missing unlearned schematics and unsupported recipe acquisition sources |
| Performance | One worst-case whole-stack batch sweep took about 0.9 seconds in the local Lua runtime, before additional ingredients | Shared planning work budget; report compared batches and incomplete sweep; faster commodity prefix lookup |
| Guidance | Workflow and limitations were scattered through commands | Help & status with version, import diagnosis, normal workflow and meaning of missing/estimated prices |

## Automated verification

- `texlua tests/run.lua`: 289 checks pass.
- Lua syntax checks cover every active module; shell syntax checks cover the installer.
- The suite includes an end-to-end Forever-shaped flow with modern profession globals absent: discover Cooking, import legacy recipes, observe a supplier, invoke Auctionator, receive commodity/whole-stack results, apply a 15% cut and two failed deposits, and compare the calculated profit with independent arithmetic.
- Cost tests compare vendor/tier optimization with brute force and whole-stack optimization with exhaustive subsets.
- UI tests exercise Hide/Show callbacks, catalogue inspection and returns, paging, settings validation, missing dependencies and empty-state messages. They do not render Blizzard textures/fonts.
- Release checks compare packaged files with source and validate the texture/manifest. Installer checks cover fresh/update installs, preserved backups and rollback on a simulated final move failure, all in temporary folders.

## Limits still visible to users

- Live UI rendering, client event ordering, AH throttling and server-provided recipe details require the in-game checklist. The game was not operated from this environment.
- Legacy windows expose learned visible recipes, not a complete list of everything available to learn. Worth Learning requires actual imported unlearned ingredients and verified trainer information. Vendor/drop recipe acquisition costs and taught-spell mappings remain unsupported.
- Recrafts, reagent choices/currencies and non-item enchant services are excluded rather than priced with incomplete costs.
- Sale prices are forecasts. Neither a profitable craft nor a farming candidate proves buyer demand or reserves listings. Manual fees, supplier travel, repairs and inventory constraints remain assumptions/omissions.
- Farming percentages are historical provider references, not measured Forever rates. Gathering skill requirements, object percentages and safe minimum levels are unknown where the provider cannot establish them. No gold/hour promise is made.
- Detailed purchases expire after 60 seconds; buyers must recheck before spending. Some item deposit quotes require the crafted output in bags or a manual override.

## Short live acceptance pass

1. Install 0.4.1, restart WoW, open `/moba`, confirm the version. Detect/save professions, open Cooking/Blacksmithing, expand groups and Refresh. Confirm recipes appear.
2. Open Catalogue, click a recipe, then Back twice. Only the intended page should be visible each time.
3. At the AH, Scan AH and wait for Auctionator. Return, click one recipe, Check each reagent and compare quantities and full costs with the actual listings. Confirm fees and the output's deposit against the posting panel.
4. Visit a spice vendor and recheck a bundle boundary. Change the cut in Fees & settings and verify that profit changes accordingly.
5. Inspect one farm at your level and one recipe deal. Confirm missing/unsupported evidence is labelled and no automatic transaction occurs.

The longer cases and failure-report fields are in [IN_GAME.md](IN_GAME.md).
