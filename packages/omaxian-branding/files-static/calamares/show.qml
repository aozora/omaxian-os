import QtQuick 2.0;
import calamares.slideshow 1.0;

Presentation {
    id: presentation
    function nextSlide() { presentation.goToNextSlide(); }
    Timer { interval: 20000; running: presentation.activatedInCalamares; repeat: true; onTriggered: nextSlide() }

    Slide {
        Image { id: bg; source: "slide1.png"; width: 800; height: 450; fillMode: Image.PreserveAspectFit; anchors.centerIn: parent }
    }
    Slide {
        Rectangle { anchors.fill: parent; color: "#0b0f14" }
        Text {
            anchors.centerIn: parent; color: "#eafffb"; font.pixelSize: 22
            horizontalAlignment: Text.Center; wrapMode: Text.WordWrap; width: parent.width * 0.8
            text: "Omaxian: the Omarchy experience on Devuan.<br/>sysvinit, XLibre, i3 + Quickshell, no systemd.<br/><br/>Super+Space opens the launcher, Super+Alt+Space the Omarchy menu."
        }
    }
    function onActivate() { presentation.currentSlide = 0; }
    function onLeave() { }
}
