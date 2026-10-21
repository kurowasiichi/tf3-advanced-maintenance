# Advanced Maintenance — Transport Fever 3 進階維修模組

模組 ID：`advanced_maintenance`

車廠、維修站與機庫可以收三種補給貨物，替它維修的車輛補給。每種補給對應一項加成：

| 補給 | 貨物 | 加成 |
|---|---|---|
| 燃油 | `::/cargos/fuel/fuel.cargo` | 最高速度 +X% |
| 家具 | `::/cargos/furniture/furniture.cargo` | 舒適度 +X% |（只有能載客的車輛）
| 機械 | `::/cargos/machines/machines.cargo` | 噪音、污染 −X% |

X 預設 20。三種補給各自計量：車輛缺少哪一種，就只有那一項回到原版數值。

## 玩法

1. 把貨物運到維修設施。設施像工業一樣收貨：在旁邊蓋貨運站，集貨範圍涵蓋設施即可。
2. 每種補給存在設施各自的庫存，上限預設 200 單位，存滿後不再收貨。
3. 設施替 `TransportVehicle.maintenanceStation` 指向它的車輛補給，任一種低於 95% 就補。
4. 車輛行駛時三種補給同時消耗。家具只有能載客的車輛會消耗（`TransportVehicle.config.capacities` 的乘客容量大於 0，整列合計，所以掛有客車廂的混合列車也算）；不載客的車輛沒有家具存量、不取家具，也沒有舒適度加成，車輛視窗不顯示家具列，維修站統計也不計入。消耗速度以燃油為 1，家具與機械為 0.5，也就是可維持「補給滿額可維持天數」的 2 倍；數值在 config.tl `Supplies` 的 `drainRate`。

新車出廠時三種補給都是滿的。加入模組前就存在的車輛也視為滿的。

## 設定

| 項目 | 選項 | 預設 | 生效時機 |
|---|---|---|---|
| 加成 | 10／20／30 % | 20 % | 下一輪更新 |
| 補給滿額可維持天數（燃油） | 30／60／90／120／180／360 天 | 90 天 | 下一輪更新 |
| 每單位貨物可補滿的車輛數 | 0.25／0.5／1–10 | 2 | 下一輪更新 |
| 設施補給存量上限 | 100／200／400／800 | 200 | 之後新建或重建的設施 |

設定都在模組參數（[mod.json](mod.json)，數值對應在 [config.tl](content/advanced_maintenance/config.tl)），同時套用在三種補給。開新遊戲時在模組設定選擇；既有存檔在讀取前的模組選擇頁修改。遊戲腳本每一輪（約 2 秒遊戲時間）讀 `api.engine.config.getModParams()`，存檔 state 不保存設定。

補滿一次消耗的貨物量以公車（道路車輛）為 1，數值在 [config.tl](content/advanced_maintenance/config.tl) 的 `VehicleFactors`：

| 載具 | 倍率 | 判斷方式 |
|---|---|---|
| 公車、卡車 | 1 | carrier `ROAD` |
| 輕軌 | 2 | carrier `TRAM` |
| 火車 | 4 | carrier `RAIL` |
| 小型船隻 | 2 | carrier `WATER`，transport mode 含 `SMALL_SHIP` |
| 大型船隻 | 4 | carrier `WATER`，其他 |
| 小型飛機、直升機 | 2 | carrier `AIR`，transport mode 含 `SMALL_AIRCRAFT` 或 `HELICOPTER` |
| 大型飛機 | 4 | carrier `AIR`，其他 |

倍率只影響補滿要多少貨物，補給條下降的速度所有載具相同，依「補給滿額可維持天數」。

## 介面

- 車輛視窗的「狀態」卡片：維修列下方依序是燃油、家具、機械三列，樣式與維修列相同（`RatingBar`），圖示是各自的貨物圖示，文字用 `vehicle_util.getConditionText` 依百分比顯示極差到極佳。
- 維修設施視窗：三種補給庫存合併在一張工業樣式的「投入庫存」卡片（`CombinedStockGroupedCounts`）。展開後顯示各補給有幾輛維修中車輛有存量。

## 實作

| 檔案 | 內容 |
|---|---|
| [content/mod.script.tl](content/mod.script.tl) | `preRunFn` 接管 `BaseConfig.constructionScript`，原本的腳本名稱與存量上限放進 params，與 smart_town 等同樣接管的模組可以串接 |
| [content/advanced_maintenance/depot_construction.script.tl](content/advanced_maintenance/depot_construction.script.tl) | 先執行原本的建築腳本（含模組），再替每個帶 `depot` 欄位的 subconstruction 加三個庫存 subconstruction，每個一種貨物：`INPUT_STOCK` 加一條 rule，寫法同 `industries/industryutil.lua`。rule 的 capacity 是 1，幾乎不消耗，只用來讓貨運路由把庫存當成收貨目的地。三個分開，讓每種補給的庫存各自計數。模型用原版的隱形模型 `::/assets/stations/air/misc/invisible.mdl`。tag 7300–7302 用來避免重複加 |
| [content/advanced_maintenance.script.tl](content/advanced_maintenance.script.tl) | 遊戲腳本，每 2 秒遊戲時間跑一輪：扣行駛中車輛的補給；補給時以 `api.cmd.debug.makeStockSetCargoAmountCmd` 從設施庫存扣掉整數單位，不足一單位的零頭留在腳本的 tank 給下一輛車；rule 偶爾消耗的量讀 `applyHistory` 一併入帳；加成狀態改變時，以 `VehicleModifier / ChangeModifier` 事件交給原版的車輛修正值腳本。每一輪讀取模組參數 |
| [content/advanced_maintenance/config.tl](content/advanced_maintenance/config.tl) | 補給清單、模組參數對照與允許值、載具倍率 |
| [content/advanced_maintenance/stock.tl](content/advanced_maintenance/stock.tl) | 找出設施的補給庫存，遊戲腳本與 GUI 共用 |
| [content/gui/advanced_maintenance/supply_eow.script.tl](content/gui/advanced_maintenance/supply_eow.script.tl) | 車輛視窗的補給列、維修設施視窗的庫存卡片 |

加成作用在 `TransportVehicle.Modifiers`：燃油改 `topSpeedScale`，家具改 `comfortScale`，機械改 `noiseScale` 與 `pollutionScale`。功率、載貨速度與營運成本沒有逐台調整的 API。

加成不直接寫進車輛，做法和地標（例如國會大廈）相同：送 `makeScriptingSendEventCmd("", "VehicleModifier", "ChangeModifier", { entity, modifications = { TopSpeed, Comfort, Noise, Pollution }, id = "advanced_maintenance" })`，由原版的 `base/content/vehicle/vehicle_modifier.script.tl` 把所有來源的增減量相加後，以 `makeVehicleSetModifiersCmd` 寫入。直接寫入會在其他來源（地標在車輛換了最近城市時就會重送）更新時被整組覆寫，飛機與船隻常換最近城市，最容易被蓋掉。舊存檔讀入時（state 沒有 `modifierRevision` 2）會清掉已套用紀錄，讓所有加成重新登記一次。

GUI 的兩處接法，都在 `doReplaceFn`（由 `advanced_maintenance_replacement.res.lua` 註冊）：

- 車輛視窗的「狀態」卡片是 `vehicle_eow.script.tl` 的 local 內容，無法替換。包裝 `content_card.makeRecipeAndParam`：建立帶維修圖示 `symbol_tools.tga` 的 `RatingBar` 時，換成「維修列＋三列補給」。GUI 沒有 `debug.getlocal`，車輛的取法是：原版在同一次同步執行中先呼叫 `engine_react_util.useStepState(makeVehicleMaintenanceState)`，取值函式內呼叫 `vehicle_util.getAvgMaintenanceState(車輛)`。模組記下最後一次傳給 `useStepState` 的取值函式，建立維修列時再呼叫一次，攔截 `getAvgMaintenanceState` 收到的車輛。
- 包裝 `cargo_util.calculateStockConfigs`：查的是設施的第一個補給庫存時，把其他補給庫存的資料併進來，三種補給就顯示在同一張卡片。

GUI 腳本裡的迴圈變數不能用 `_`，否則會蓋掉翻譯函式 `_()`。自訂 recipe 的根節點必須是 layout。放進視窗容器的視窗要用 `RegisterWrapperRecipe(..., builtin.Window, ...)` 註冊。

GUI 讀取 state 用 `gameScriptSystem.getEntityForGameScript("advanced_maintenance::/advanced_maintenance.gs")`。

## 待驗證

- 貨運路由是否把家具與機械送往設施的庫存。
- `api.cmd.debug.makeStockSetCargoAmountCmd` 在正式版遊戲是否生效（原版除錯面板也用它）。log 摘要的 `in stock` 是庫存量，`taken` 是已取出、尚未補給給車輛的量，正常應小於 1。
- 腳本讀庫存與寫回之間送達的貨物會被寫回的數量蓋掉，最多損失一輪（2 秒遊戲時間）內送達的量。
- productivity 0 無法讓 rule 停止消耗，已確認，不再使用。
- 門口自帶停靠站尚未實作，目前所有設施都用集貨範圍收貨。

加入模組前就蓋好的設施沒有補給庫存；舊版建造、只有燃油庫存的設施沒有家具與機械庫存。重建或升級後才有。

## 開發

- 語言：Teal `.tl`。型別定義取自遊戲的 `api/tealdef`、`base/tealdef` 與 [tealdef/](tealdef/)。
- 型別檢查：`powershell -ExecutionPolicy Bypass -File tools\check.ps1`，`tl` 0.24.7 需在 PATH 中。
- 部署：`powershell -ExecutionPolicy Bypass -File tools\deploy.ps1`（staging area），`-Target Mods` 部署到使用者模組目錄，`-Remove` 移除。
- 遊戲 log：`%SteamPath%\userdata\<id>\3493540\local\crash_dump\stdout.txt`，篩選 `[advanced_maintenance]`。

## 測試步驟

1. 開新遊戲並啟用模組，log 出現 `[advanced_maintenance] state initialized`，之後約每 60 秒遊戲時間印一次摘要。
2. 建公車路線與道路維修站。公車視窗「狀態」卡片的維修列下方有燃油、家具、機械三列，從極佳往下降。
3. 讀檔前在模組設定把天數改成 30 天，三列下降比預設 90 天快；某一列降到 0 後，只有對應的數值回到原版。
4. 蓋貨運站讓集貨範圍涵蓋維修站，分別送燃油、家具、機械。維修站視窗的投入庫存卡片列出三種貨物，車輛補滿。
5. 鐵路車廠、港口維修站、機場機庫各測一次。
6. 存檔、讀檔：補給量與庫存保留，設定值依存檔的模組設定。
