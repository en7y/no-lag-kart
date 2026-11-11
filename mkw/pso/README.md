# Warm-up (prewarm) lists for Mario Kart World 1.8.0

`pso_manifest_merged_180.tsv` is what this Mac's build has as its profile `pso_manifest.tsv`: every list that could be found online on 2026-11-11 plus this Mac's own,
merged in the order below by `mkw/merge_pso_lists.py --map <the build's shader_map.tsv>`, which keeps only rows this host takes (every shader in the 1.8.0 map, at the
stage the map gives it): 15,049 rows (6,827 shaders, 7,989 render pipelines, 222 compute pipelines, 11 task / mesh pipelines). The host reads it at every start and
builds each row before the first frame ("Preparing shaders").

## Sources (`src/`)

| file | from | rows | new rows it adds | notes |
|---|---|---|---|---|
| `a_pr2097_iphone_180.tsv` | seedds/nxnative pull request #2097, head `1a4fd595` (also oliverames/nxnative `mkw-prewarm-duo-20261109`) | 9,342 | 9,312 | an iPhone, 1.8.0, about 15 launches; 30 rows use NVN2's stage numbers 6 / 7 and are left out |
| `b_thijs_180.tsv` | Thijs2004/nxnative-mkw `b1c5e4e5`, `dm/games/0400C3F00006E000/pso_manifest.tsv` | 10,582 | 1,608 | 1.8.0; 38 rows run task and mesh shaders as compute shaders and are left out (19 of them crashed the prepare step) |
| `c_s2m_nxnative-mkw_180.tsv` | azmasm/switch2mac `ef0b08cb`, `games/mario-kart-world/shader_list-nxnative-mkw.tsv` | 123 | 68 | |
| `d_s2m_nxnative_v0.tsv` | the same commit, `shader_list-nxnative.tsv` | 13,431 | 2,697 | the base game (v0): rows of shaders 1.8.0 does not have are left out |
| `e_s2m_mkw-neo_v0.tsv` | the same commit, `shader_list-mkw-neo.tsv` | 13,328 | 1,130 | v0 |
| `f_m2pro_mac_180.tsv` | this Mac's `pso_user.tsv` after two races | 7,050 | 13 | everything else this Mac met was already in the lists above |
| `g_cheemu21_v0.tsv` | cheemu21/plumber-racer-2 `843170ac`, `dm/games/0400C3F00006E000/pso_manifest.tsv` | 10,523 | 10 | v0 |
| `h_pahorema_v0_oldkeys.tsv` | pahorema/kartnative `47f2d1d5`, `dm/games/0400C3F00006E000/pso_manifest.tsv` | 6,521 | 15 | an older key scheme: rewritten to `h_pahorema_v0.tsv` |
| `i_s2m_engine_v0_oldkeys.tsv` | azmasm/switch2mac `ef0b08cb`, `games/mario-kart-world/shader_list.tsv` | 13,957 | 196 | the same older scheme: rewritten to `i_s2m_engine_v0.tsv` |
| `map_pahorema_v0.tsv` | pahorema/kartnative `47f2d1d5`, `dm/games/0400C3F00006E000/shader_map.tsv` | | | the old scheme's shader map, for the rewrite |

Each download was checked against its git blob ID. Two more files named `pso_manifest.tsv` exist for this game online and hold no rows: oliverames/nxnative
(`pr-1383-deploy` and two more branches) and aksmith-git/nxnative (`mkw-memory`). Upstream's own profile ships a two-line placeholder.

## Old keys

pahorema/kartnative and switch2mac's own engine hash each shader differently from upstream, so none of their keys is in upstream's map. Both lists are for the base game,
and so is upstream's map in `dm/games/0400C3F00006E000/shader_map.tsv`. `translate_keys.py` joins the two maps on `(package, source location)`, which is unique in each and
names the same bytes of the same file, and rewrites every key (11,552 of 11,560 shaders join). The check of the result is the merge itself: of the 6,512 rewritten
pahorema rows, 6,452 are rows another list already has, 45 the filter leaves out and 15 are new; of switch2mac's 13,948: 13,700, 52 and 196.

    python3 mkw/pso/translate_keys.py mkw/pso/src/h_pahorema_v0_oldkeys.tsv mkw/pso/src/map_pahorema_v0.tsv dm/games/0400C3F00006E000/shader_map.tsv -o mkw/pso/src/h_pahorema_v0.tsv
    python3 mkw/pso/translate_keys.py mkw/pso/src/i_s2m_engine_v0_oldkeys.tsv mkw/pso/src/map_pahorema_v0.tsv dm/games/0400C3F00006E000/shader_map.tsv -o mkw/pso/src/i_s2m_engine_v0.tsv

Do not join on `(package, index)`: the two splits number the shaders of a package differently from some point on. That join gave thousands of plausible, wrong rows,
and the stage always agreed, because a package holds one stage.

## Making the merged list again, and checking it

    python3 mkw/merge_pso_lists.py --map <build>/profile/0400C3F00006E000/shader_map.tsv -o mkw/pso/pso_manifest_merged_180.tsv mkw/pso/src/[a-g]_*.tsv mkw/pso/src/h_pahorema_v0.tsv mkw/pso/src/i_s2m_engine_v0.tsv
    mkw/test/prep_probe.sh mkw/pso/pso_manifest_merged_180.tsv        # builds every row in the real prepare step, away from the game's own files
    cp mkw/pso/pso_manifest_merged_180.tsv <build>/profile/0400C3F00006E000/pso_manifest.tsv

A list from anywhere else goes through the same commands first. The host drops a row it cannot take by itself, but only since our commit "A prewarm line that names a
shader at another stage than the shader map's is left out"; upstream's host does not.
