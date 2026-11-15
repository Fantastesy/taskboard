// Merkt, wenn ein anderes Programm aktiv wird (Klick in sein Fenster, Alt+Tab), damit die Seitenleiste sofort
// hinausfaehrt (SidePanel.qml). Unter Wayland sieht ein Widget keine Klicks in fremden Fenstern, nur diesen Wechsel.
// Eigene Datei, per Loader geladen: fehlt das Modul org.kde.taskmanager, laeuft der Rest des Widgets trotzdem.
import QtQuick
import org.kde.taskmanager as TaskManager

Item {
    signal otherAppActivated()

    TaskManager.TasksModel { id: tasks }

    Connections {
        target: tasks
        function onActiveTaskChanged() {
            var idx = tasks.activeTask;
            // kein Fenster aus der Taskleiste (Desktop, eigene Seitenleiste): nichts tun
            if (!idx || idx.row < 0) return;
            var app = String(tasks.data(idx, TaskManager.AbstractTasksModel.AppId) || "");
            // eigene Fenster (Formular, Einstellungen) gehoeren zu plasmashell
            if (app.indexOf("plasmashell") >= 0) return;
            otherAppActivated();
        }
    }
}
