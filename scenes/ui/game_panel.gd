class_name GamePanel extends PanelContainer
## A PanelContainer wearing the shared window style (UiTheme.panel_style), for
## panels placed in a scene rather than built through ModalPanel.


func _ready() -> void:
	UiTheme.apply_panel_ninepatch(self)
