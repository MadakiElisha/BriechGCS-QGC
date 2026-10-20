import QtQml.Models

import QGroundControl
import QGroundControl.Controls

ToolStripActionList {
    id: _root

    signal displayPreFlightChecklist

    model: [
        ToolStripAction {
            text: viewer3DWindow.isOpen ? qsTr("Fly Map") : qsTr("3D View")
            iconSource: viewer3DWindow.isOpen ? "/qmlimages/PaperPlane.svg" : "/qml/QGroundControl/Viewer3D/City3DMapIcon.svg"
            visible: true
            onTriggered: {
                if (viewer3DWindow.isOpen) {
                    viewer3DWindow.close()
                } else {
                    QGroundControl.settingsManager.viewer3DSettings.enabled.rawValue = true
                    viewer3DWindow.open()
                }
            }
        },
        PreFlightCheckListShowAction { onTriggered: displayPreFlightChecklist() },
        GuidedActionTakeoff { },
        GuidedActionLand { },
        GuidedActionRTL { },
        GuidedActionPause { },
        FlyViewAdditionalActionsButton { },
        GuidedToolStripAction {
            text:       _guidedController._customController.customButtonTitle
            iconSource: "/res/gear-white.svg"
            visible:    true
            enabled:    true
            actionID:   _guidedController._customController.actionCustomButton
        }
    ]
}
