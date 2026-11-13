# MobAuction — WoW Forever

MobAuction finds crafting opportunities for your character's professions, checks ingredient quantities against detailed AH listings, flags discounted recipe items, compares recipes worth learning, and ranks farming candidates using recent AH prices and reference loot data. The launcher is **`/moba`**, with **`/mobauction`** as an alias. It does not register `/ma` or `/fp`.

Version 0.6.1 targets Forever interface 16001. The custom Tommy gun icon appears in the AddOns list and window title.

## Install or update

Download `MobAuction-0.6.1.zip` from the GitHub Releases page. Extract it so the game has this exact file:

```text
World of Warcraft/_forever_/Interface/AddOns/MobAuction/MobAuction.toc
```

Replace the previous `MobAuction` folder when updating. Do not install GitHub's automatically generated **Source code** archive; use the attached `MobAuction-0.6.1.zip` release asset because it has the correct addon-folder layout.

Developers can install a checkout with the included staging installer by passing the AddOns directory explicitly:

```bash
bash install.sh "/path/to/World of Warcraft/_forever_/Interface/AddOns"
```

It backs up an existing MobAuction or retired ForgeProfit folder under `AddOns/.MobAuction-backups/` and restores it if installation fails.

Restart WoW, enable **MobAuction** (Auctionator is optional for full scans), then type `/moba`. Confirm the version displayed inside the window matches the update: replacing files on disk does not change the copy already running in WoW. AHledger is optional for crafting, but supplies historical recipe-deal comparisons and estimated demand for learning flags. Enable your installed **Questie** and **QuestieDB** for the Recommended Farms tab. This update retains your saved character settings. For manual ZIP installation, disable or remove the old ForgeProfit folder.

MobAuction 0.2 settings are retained, with character setup required once. Its old Classic requirements and unversioned manual requirements no longer count as verified. Old ForgeProfit saved settings are not imported.

## Changes in 0.6.1

Worth Learning now opens on the bounded **AH recipes** view, restricts catalogue evaluation to the character's selected professions, reuses one reference view, and coalesces item-data updates. Unrelated auction events no longer rebuild the entire learning catalogue, preventing the interface freeze seen with large reference databases.

The full-scan cooldown message now distinguishes a completed usable snapshot from a recent request that did not produce one. WoW's approximately 15-minute restriction begins when a full-scan request is sent, not when MobAuction finishes reading it.

## Changes in 0.6.0

**Full AH scan** requests the server's entire auction-house snapshot. One scan prices materials, crafted outputs and recipe/plan listings together, even with no imported recipes. It processes rows across frames, shares completed scans made by other addons, and reports incomplete responses honestly. Keep the AH open until completion. Full scans share an approximately 15-minute server cooldown; repeatedly clicking cannot bypass it.

**Worth Learning** has **Learning: all sources** and **Learning: AH recipes** filters. The first combines catalogue research, observed trainer offers and auctioned recipes; the second focuses on recipe items offered in the scan. Click a row for ingredients, profit and learning checks. Recipe purchase/training cost stays separate and never changes craft profit or ranking.

A separate reference catalogue discovers recipes across professions in small batches and validates their current output and ingredients through the client. Historical discovery IDs are only search hints. Reference entries never teach your character recipes or overwrite imported learned status. Catalogue and Help & status report coverage; complete Forever coverage is not claimed.

The optional [Recipe Registry Forever](https://www.curseforge.com/wow/addons/recipe-registry) database supplies additional recipe IDs, ingredients and recipe-item associations when installed and enabled. Its data is shown as reference research until confirmed by the client. Its source may be from a different game build; skill requirements and learnability must still be checked. Install its **Forever** release, not the TBC release.

Snapshot prices are minimum asking prices, not reserved stock or a promise of sales. A fresh full snapshot takes precedence over older addon prices, including when it reports no buyout listing for an item. Detailed ingredient checks still account for full stacks and price tiers. Missing item prices remain unknown.

## Previous changes in 0.5.1

Uses the requested **assumed deposit of 1 silver per output item** by default. Fees & settings can switch back to actual game quotes. The assumption is labeled and includes configured failed listings. Upgrade enables scan forecasts once; future pricing choices persist. Detailed quantity checks can still verify supply before purchasing.

Both crafting and learning lists sort by **Sale profit descending**, including known sale profits whose adjusted profit is still unknown. Mouse-wheel scrolling works over the list and recipe rows; Previous/Next remain available. Worth Learning shows recent ingredient-price forecasts and displays unmapped recipe listings with their asking price and an explicit need for crafting data. Unknown ingredients are never free.

The earlier recipe-only browse scanner is retained internally for compatibility. The main interface now uses the unified full snapshot described above.

## Previous changes in 0.5.0

Opening a profession automatically imports its plans or recipes and retries while the data loads. Closing or switching professions cancels pending work. You do not need `/moba refresh` to import. The optional Refresh button still recalculates costs and reports import status.

Crafting opportunities sort by highest **Sale profit**, with unknown profits last. Confidence and failed-listing losses remain visible in their own columns. Automatic deposits use the game's calculation and reuse recent quotes during the same AH visit. Commodities can be quoted without owning the output; other items still need one output in your bags because the game requires its bag location.

**Worth Learning** can inspect auctioned recipe items as well as trainer recipes. It displays **Learn price** separately and sorts by **Sale profit**, including materials, AH cut and expected failed deposits. The recipe or trainer price is never deducted from crafting profit and never changes the ranking. See the learning workflow below.

## Previous changes in 0.4.4

Fixed **Open the auction house first** appearing while the AH window is open. AH detection now checks the visible modern or legacy auction window, matching Auctionator's search API, and listens to modern Auctioneer interaction events as well as older AH events. Crafting/farming scans, ingredient checks, deposits and recipe deals use the same detection. A stale open flag cannot authorize a search after closing the window; cached detailed listings and bargains are cleared between visits. Opening the AH still does not start a scan automatically. Help & status reports whether the AH is currently open.

## Previous changes in 0.4.3

Blacksmithing now uses **plan/plans** in the list, details and catalogue. Status starts with the selected profession's count, for example **Blacksmithing: 0 plans saved; 0 ready for price searches**. The total across all professions is shown separately, and Cooking exclusions no longer appear as Blacksmithing problems.

Modern imports follow Forever's selected-profession lookup and readiness checks. An individual entry still loading no longer blocks every other validated entry; conflicting profession identities still block unsafe imports. Clicking Refresh reports the imported count or the reason it could not import. The addon records the version actually initialized and its latest active import attempt for diagnosis. These changes address concrete compatibility gaps; the latest reported empty Blacksmithing view still requires a live-client check.

## Previous changes in 0.4.2

Fixed Cooking recipes being saved under Fishing when the global profession and cached recipe list disagreed. Modern imports now validate each recipe's profession and a stable source before saving; closed profession windows use saved imports for filters, Refresh and AH searches. Loading data cannot overwrite a complete saved observation. Trainer and skill evidence are retained only for the same profession, output and build.

**After updating:** reopen Cooking and Blacksmithing, one at a time, and let their crafting lists load. The current version imports automatically. Older modern imports require this repair once because their saved profession labels cannot be trusted. Correct legacy imports remain valid. Close the profession windows afterward; imported recipes remain available in `/moba` at the AH. **Use detected levels** clears manual overrides for selected professions that WoW currently detects, so an older Cooking preview of 225 does not hide recipes observed at 244. Manual overrides remain available and are now visible beside detected ranks.

## Previous changes in 0.4.1

Fixed overlapping Catalogue/detail windows, missing imports from legacy profession windows, Forever skill detection and vendor pricing field compatibility. Added clickable Catalogue rows, Back navigation, Fees & settings, Help & status, specific empty-state messages, automatic skill tracking when accepting detected ranks, and a shared work limit for batch planning. The audit and validation boundaries are recorded in [tests/AUDIT.md](tests/AUDIT.md).

## First-run character setup

On first login/open, MobAuction asks which professions your character has. **Detect my professions** reads primary and secondary professions and their current skills from WoW, including Cooking and First Aid. Review the selections and click **Save character**. You can select manually if the client does not return professions. Blank fields and unchanged detected ranks follow your detected skill as you gain points. Entering a different rank sets a manual preview; `/moba skill cooking auto` restores automatic detection. Discovery supports Forever’s `C_SkillInfo`, including direct lookups when headers are collapsed, as well as older profession/skill APIs. Run `/moba setup` to revisit them.

All twelve standard Forever professions are listed, and additional professions returned by the client are recognized. Gathering professions can be selected, but have no craft-profit rows unless their client recipe data actually describes an item-producing craft. Mining's smelting recipes are supported. Enchantments without a saleable item output are marked unsupported rather than assigned a fabricated auction value.

Open each selected crafting profession window once to import the recipes the client exposes, including unlearned recipes where schematics are available. Visit ingredient suppliers to record unlimited, gold-only stock and prices. Visit profession trainers after importing recipes to record their requirements, availability and gold training costs.

## Crafting and batch costs

The workflow is **set up → open professions → Full AH scan → choose Crafting or Worth Learning → check ingredients**. The full scan supplies market prices independently of recipe imports; opening professions supplies character knowledge. Selected professions and skill levels filter opportunities, without limiting the AH snapshot. Unknown requirements remain research until confirmed.


1. At the AH, click **Full AH scan** and wait for a completed snapshot. No recipe import is needed to scan the market. The result includes material, output and recipe-item prices.
2. Open `/moba` and click a recipe. In **Batch check**, click **Check** for each ingredient to request detailed AH listings. Click again if more pages are needed. These are explicit, throttled user requests; let other AH scans finish first.
3. Change **Crafts** and press **Apply**. Commodity costs consume the cheapest available quantity at each price tier. Noncommodity costs choose whole buyout stacks, including overbuying when unavoidable. Bid-only listings and your own/account auctions are excluded.
4. Supplier bundles can be combined with auction purchases when that costs less. Supplier observations expire after seven days; discounts can change sooner.
5. **Best batch (1–100)** checks those batch sizes and reports the highest supported forecast profit. It does not claim a global optimum or account for sales demand.

Detailed price books expire after **60 seconds** and clear on AH close/reopen, purchases, postings or cancellations. Partial data, insufficient stock, missing prices and missing deposits remain explicit. Browse minimum prices do not prove full-batch availability.

The optional **Pricing: checked listings** mode uses fresh complete listing books or recorded supplier prices. **Pricing: scan estimates** uses fresh full snapshots first and can use Auctionator/AHledger scalar prices when no current quantity book exists; estimate rows are amber. Crafting rows sort by Sale profit regardless of cost confidence; known losses precede unknown profits. An observed shortage never silently falls back to an old minimum price. Whole-stack optimization is bounded at 1,000 requested units and 500 listings per ingredient; larger problems remain unknown or use an available vendor quote. The 1–100 batch sweep also has a shared work budget so several difficult ingredients cannot freeze the game; the result reports how many batches were fully priced and warns if larger batches were not compared. Commodity tier lookup uses cumulative costs and binary search.

Owned ingredients retain replacement cost. Duplicate reagent slots are aggregated. Variable-output recipes use their minimum yield. Optional/reagent-choice recipes that this version cannot cost are marked unsupported. Recursive crafting of intermediates is not implemented.

## Profit and deposits

**Fees & settings** (or `/moba settings`) lets you edit auction cut, listing duration, expected failed listings and allowed price age without slash-command arguments. Defaults are assumptions, not automatic AH-type detection. All fields validate together before saving. **Help & status** (`/moba help`) shows the workflow, version and import status. Missing deposit quotes are labelled separately from missing material/sale prices; known material costs remain visible when the output price is unknown.


- Sale profit = output price forecast minus auction cut minus materials.
- Adjusted profit = sale profit minus the deposit for each assumed failed listing. Defaults: 5% cut and one failure before a successful sale.
- The successful listing's deposit is returned, so it is not deducted again.
- Cash required includes material costs and deposits through the final listing.

The default is the requested **assumed 1 silver deposit per output item**. Fees & settings can switch to actual game quotes. In that mode, commodity deposit quotes come from the game's calculation for the exact whole output quantity without requiring ownership. Noncommodity quotes use an output item in your bags and assume individual listings. Quotes are cached for up to 60 seconds for the same AH visit, build and duration; bag changes invalidate them. Failed/loading quotes are retried when recalculating, and a real zero is accepted. Missing quotes remain unknown; an optional verified per-output-unit override is available with `/moba deposit ITEMID COPPER` for the chosen duration. Cut and duration remain configurable. Select the appropriate cut manually for the house you use.

Sale prices are forecasts from a fresh completed full AH snapshot, then recent Auctionator prices or AHledger's current-market minimum when no valid snapshot exists. Historical/seed snapshots and stale references are rejected where described. A checked ingredient cost does not guarantee a sale or reserve those listings.

## Verified coverage and skills

The active addon no longer uses the Classic requirement table. Recipes come from the client, with game-build and observation metadata. The modern reader imports available schematics; the legacy TradeSkill/Craft readers import visible learned entries, preserving minimum yield, quantities and links. Expand profession groups to include their recipes. Missing reagent links are retried while the profession window is open. Temporary local recipe IDs are negative when the client provides no spell link and are replaced if a spell link later becomes available. It does **not** claim a complete catalogue of every Forever recipe: coverage depends on the recipes the client exposes and the profession windows/trainers you visit.

A minimum skill is verified by a matching trainer spell ID, recipe name, profession name and current-build recipe observation, or by your explicit build-specific confirmation. Merely knowing a recipe at skill 150 proves it is usable at that observed skill; it does not reveal whether its minimum was 1 or 125. A simulated lower skill requires a known minimum. Old-build recipe observations are excluded until reopened. If live profession detection succeeds, recipes from professions the character no longer has are excluded.

**Catalogue** displays known/unlearned state, minimum requirement provenance, missing data and unsupported outputs. Click a recipe to open its batch check, including unlearned recipes. It shows twenty recipes per page and scrolls within each page. Back, X or Escape returns to the previous window. Only one MobAuction page is shown at a time. Manual confirmation: `/moba requirement RECIPEID LEVEL`; clear it with `clear` in place of LEVEL.

## Worth Learning

**Client coverage limitation:** a legacy profession window may only expose learned recipes. When no unlearned schematics have been imported, this feature now explains that limitation instead of directing you through an impossible loop. It does not invent ingredient lists from trainer names. Client-validated reference recipes and an optional Recipe Registry Forever database can extend the catalogue beyond your imported recipes; unavailable entries remain clearly marked.


**Worth Learning** or `/moba learn` compares unlearned auction and trainer recipes for your selected professions and skill. All rows use **one craft**, regardless of the batch selected on the normal Crafting page. **Profit / craft** subtracts materials, the AH cut and expected failed deposits. **Learn price** shows the recipe purchase or trainer cost separately; it is never deducted from profit, included in payback calculations or used for ranking.

At the AH, click **Full AH scan**, then turn Worth Learning on. Choose **Learning: AH recipes** to restrict the list to auctioned recipe items, or **Learning: all sources** to include catalogue research. Click a candidate and **Check** its ingredient quantities. The purchase row also offers Check to replace a browse price with an observed whole-listing cost; this does not affect craft profit. Recipe coverage is limited to the listings returned and exact item-to-recipe mappings that the client can validate. The addon does not match recipes by similar names.

Confirmed auction candidates require an exact client recipe identity, selected profession, current unlearned state and supported ingredients. Database-only entries can show estimated profits as research, but cannot earn a confirmed learning flag. The client's item usability check establishes current learning eligibility; a manual higher skill cannot make an unusable recipe learnable. Unknown mappings, requirements and costs remain explicit. A **Worth learning** flag requires positive craft profit with checked materials and deposit, confirmed usability, and recent nonsnapshot AHledger estimated market sales of at least one output unit per day. Profitable rows without demand evidence remain candidates to investigate. Estimated market sales are not a guarantee that your item will sell. Recipe price does not control the flag.

Trainer entries still require current-build recipe/requirement evidence, an availability observation no more than an hour old, a known gold training price, checked ingredient costs, sale-price data and a deposit quote. Vendor and dropped recipe acquisition outside observed AH listings remain unsupported.

## Recipe bargain alerts

While you browse/search the AH, MobAuction checks recipe-class items across **all professions**. A candidate must be at least **40% below** AHledger's 7-day median (30-day fallback) and save at least **1,000 copper / 10 silver**. The historical table must be current under the configured age limit and must not be a shipped seed snapshot.

Alerts are chat messages, limited to three per browse update and once per item per 30 minutes. **Recipe deals** shows fresh candidates and marks matches to selected professions when the recipe subclass identifies one. Observations expire after five minutes or on AH close. Items absent from viewed/search results are not monitored; this is not a whole-market background scan.

The reference is historical asking price, not a guaranteed sale price. Learning requirements, whether you already know the recipe, and remaining stock need checking. The recipe-deal view and Worth Learning view therefore make different claims.

## Recommended Farms

Open **Recommended Farms** in the main window, or use `/moba farms`. The tab starts at your current character level; **Apply** lets you preview another level and **Detect** restores your live level. **Within my level** filters NPC sources to that level. **All levels + unknown** also exposes higher-level sources and gathering objects whose requirements are unavailable.

Each row shows the item, **suggested minimum character level**, after-cut value per item, reference drop percentage, modeled value per 100 kills, and a zone. Click it for creature/object names, zone coordinates, per-source rates and provenance, alternative sources, and a deposit quote when available. The minimum is the **highest NPC level at the selected source**, not an equip requirement or a guarantee that your character can safely solo it. Elite/rare creatures, friendly NPCs, known dungeons and unidentified outdoor maps are excluded. Gathering objects show **?** for level and rate: the provider does not expose verified gathering skill requirements or object drop percentages.

Click **Scan farm prices** with the AH open to search the eligible farm items through Auctionator. Let the searches finish, return to `/moba farms`, and **Refresh**. Cached prices must meet `/moba age`; a scan is user initiated, not a background AH scan. Missing item names trigger loading and a retry message. Missing or stale prices never become zero-cost or guaranteed-profit recommendations.

Candidates include common cloth, leather, ore, herbs, cooking ingredients and elemental materials, plus reagents from your imported current-build recipes. This is not a catalogue of every farmable item. Sources are queried from the enabled QuestieDB public contract (version 4), with Questie's zone and drop-rate APIs. Missing or incompatible providers show a message without disabling crafting. No third-party loot database is copied into this addon.

**Ranking:** sources with a supported percentage come first, sorted by `(asking price - rounded AH cut) × drop percentage` as modeled value for 100 kills. This assumes one item per successful drop; it does not measure stack sizes, kill speed, spawn density or gold per hour. Unknown-rate candidates follow, ordered only by after-cut unit value, as places to investigate. Higher-priced rare drops do not imply reliable earnings or buyer demand. The tab ranks each item separately, not the combined loot from a route.

**Data limits:** the installed provider's rates include historical Wowhead/private-server references and Questie corrections; they are explicitly labelled **not measured Forever rates**. Missing percentages remain unknown, invalid percentages are rejected, and an explicit 0% source is excluded. Locations and levels can also differ on Forever. NPC loot method, quest gating, faction access to objects and gathering requirements need in-game confirmation. Reference coordinates show up to three spawn points per zone, not a farming route.

Farming values are **after the AH cut but before deposits and other expenses**. Details show a single-item deposit and modeled failed-listing loss when the game can quote it, or a manual override exists; otherwise these remain unknown. Successful sales refund deposits. Travel, repairs, relisting, training, competition and sell-through are not included in the ranking, which is a comparison of candidate loot values rather than a net-profit or gold/hour promise.

## Commands

| Command | Purpose |
| --- | --- |
| `/moba` | Open setup or main interface |
| `/moba setup` | Select/detect character professions and skills |
| `/moba help` | Workflow, installed version and import status |
| `/moba settings` | Edit fees, duration, failed listings and price age |
| `/moba scan` | Auctionator searches at open AH |
| `/moba refresh` | Optional manual import/status check and cost recalculation |
| `/moba catalogue` | Inspect recipe coverage and missing verification |
| `/moba recipe 2538` | Inspect a recipe's batch costs |
| `/moba learn` | Worth Learning recommendations |
| `/moba deals` | Current recipe bargain candidates |
| `/moba farms` | Recommended Farms with level filter and clickable locations |
| `/moba skill alchemy 150` | Manual skill by profession name or ID |
| `/moba skill first aid auto` | Restore detected skill |
| `/moba crafts 5` | Batch size, 1–1000 |
| `/moba cut 5` | Auction cut percentage |
| `/moba duration 1` | Short/medium/long duration index: 1/2/3 |
| `/moba failures 1` | Failed listings before a sale |
| `/moba age 1` | Maximum scalar/reference price age in days |
| `/moba deposit 12345 100` | Per-unit deposit at the current duration |
| `/moba cleardeposit 12345` | Remove deposit overrides |
| `/moba requirement 2538 1` | Confirm a minimum skill for this build |
| `/moba requirement 2538 clear` | Clear manual confirmation |
| `/moba alerts on` or `off` | Enable/disable recipe deal alerts |
| `/moba discount 40` | Minimum recipe discount percent |
| `/moba saving 1000` | Minimum recipe savings in copper |

## Validation and limits

```bash
texlua tests/run.lua
texluac -p MobAuction/*.lua
bash -n install.sh
```

The automated suite uses mocked APIs and includes startup, profession detection/setup, rank boundaries, recipe coverage, tier and whole-stack costs, supplier bundles, missing/expired data, purchases, trainer recommendations, alert suppression, farm provider failures, source/level/faction filters, missing rates, reference-value math, farm scans and UI construction. The current suite passes **753 checks**, including complete legacy/Forever-shaped setup-to-profit flows, window return navigation, Cooking/Blacksmithing import persistence, selected-child profession identity, asynchronous readiness, partial loads, plan wording, selected-profession counts, visible AH detection, modern auctioneer events, bounded automatic imports, profit ordering, exact deposit caching, auction recipe mappings/eligibility, and separate learning-price UI. In-game validation is still needed; this environment cannot run the WoW UI. Mock tests cannot prove rendering, live API timing or server data coverage.

See `tests/IN_GAME.md` for the acceptance checklist. No addon action automatically purchases, trains, crafts, posts or cancels anything. Supplier travel, training travel, inventory capacity, demand and player competition are not priced into forecasts.

The icon's full-resolution master and imagegen prompt are in `assets/`. The game texture is the uncompressed 128 x 128 TGA `MobAuction/Media/Icon.tga`. Retired Classic skill data and its license are archived under `tools/legacy-classic-data/` and are not shipped in the addon.

API references: [Forever auction API](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/AuctionHouseDocumentation.lua), [Forever trainer UI](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_TrainerUI/Mainline/Blizzard_TrainerUI.lua), installed Auctionator public API, and [AHledger public addon API](https://ahledger.com/developers#addons).

Farming provider references: [QuestieDB public API](https://github.com/Questie/QuestieDB/blob/master/docs/api.md), [Questie drop-rate accessor](https://github.com/Questie/Questie/blob/master/Database/QuestieDB.lua). The adapter was checked against the installed Forever addons; live-client verification is still required.

Compatibility contracts checked during the audit: [Forever skill API](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/SkillInfoDocumentation.lua), [merchant API](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/MerchantFrameDocumentation.lua), and the locally installed Auctionator/AHledger profession readers.

Recipe attribution uses the client contracts in the [Forever trade skill API](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/TradeSkillUIDocumentation.lua) and [profession info structure](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/TradeSkillUITypesDocumentation.lua).

Auction learning contracts: [Forever item spells/usability](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua), [tooltip line types](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/TooltipInfoSharedDocumentation.lua), and the installed AHledger `API.lua` documentation for estimated `soldPerDay`. Tooltip spell IDs, when present, are treated only as candidates until actual recipe data validates them.
