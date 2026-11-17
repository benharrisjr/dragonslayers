class_name AchievementListData extends Resource

## The complete achievement roster in one inspector-editable resource
## (data/achievements/achievements.tres). To add an achievement: add an entry
## here, register the matching API Name on the Steamworks partner site
## (tools/steam_achievements exports the upload files), and run
## tests/steam_check.tscn, which checks the roster is coherent.

@export var achievements: Array[AchievementData] = []
