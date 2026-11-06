"""Prépare le projet Android généré par `flutter create` pour Aura.

- visible sur Android TV (leanback, pas d'écran tactile obligatoire, bannière) ;
- nom « Aura » ;
- accès réseau, y compris en http vers un Jellyfin local ;
- droit de lancer VJOD avec les liens moonfin:// (visibilité des paquets, Android 11+) ;
- notifications du lendemain (« Alors, ce film ? ») : permission, récepteurs de
  flutter_local_notifications, et désucrage Java dans build.gradle ;
- mise à jour automatique, comme VJOD : droit d'installer des paquets, et
  l'activité principale remplacée par celle de `tool/android/` (canal
  `fr.vjod.aura/mise_a_jour`).

Le script peut être relancé : il ne modifie que ce qui manque.
"""
import re
import sys
from pathlib import Path

chemin = Path(sys.argv[1] if len(sys.argv) > 1 else "android/app/src/main/AndroidManifest.xml")
xml = chemin.read_text(encoding="utf-8")


def avant(balise: str, ajout: str) -> None:
    global xml
    if ajout.strip() not in xml:
        xml = xml.replace(balise, ajout + balise, 1)


avant("<application", '    <uses-permission android:name="android.permission.INTERNET"/>\n')
avant("<application", '    <uses-feature android:name="android.software.leanback" android:required="false"/>\n')
avant("<application", '    <uses-feature android:name="android.hardware.touchscreen" android:required="false"/>\n')

xml = re.sub(r'android:label="[^"]*"', 'android:label="Aura"', xml, count=1)
if "android:banner=" not in xml:
    xml = xml.replace("<application", '<application\n        android:banner="@mipmap/ic_launcher"', 1)
if "usesCleartextTraffic" not in xml:
    xml = xml.replace("<application", '<application\n        android:usesCleartextTraffic="true"', 1)

leanback = '<category android:name="android.intent.category.LEANBACK_LAUNCHER"/>'
if leanback not in xml:
    xml = xml.replace(
        '<category android:name="android.intent.category.LAUNCHER"/>',
        '<category android:name="android.intent.category.LAUNCHER"/>\n                ' + leanback,
        1,
    )

moonfin = '<data android:scheme="moonfin"/>'
if moonfin not in xml:
    intent = (
        "\n        <intent>\n"
        '            <action android:name="android.intent.action.VIEW"/>\n'
        f"            {moonfin}\n"
        "        </intent>"
    )
    if "<queries>" in xml:
        xml = xml.replace("<queries>", "<queries>" + intent, 1)
    else:
        xml = xml.replace("</manifest>", f"    <queries>{intent}\n    </queries>\n</manifest>", 1)

avant("<application", '    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>\n')
avant("<application", '    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>\n')
avant("<application", '    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>\n')

recepteurs = """
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"/>
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver"/>
"""
if "ScheduledNotificationReceiver" not in xml:
    xml = xml.replace("</application>", recepteurs + "    </application>", 1)

chemin.write_text(xml, encoding="utf-8")
print(f"Manifeste prêt : {chemin}")

# Désucrage Java, demandé par flutter_local_notifications.
app = chemin.parents[2]
for nom in ("build.gradle.kts", "build.gradle"):
    gradle = app / nom
    if not gradle.exists():
        continue
    g = gradle.read_text(encoding="utf-8")
    kts = nom.endswith(".kts")
    if "desugar_jdk_libs" not in g:
        active = "isCoreLibraryDesugaringEnabled = true" if kts else "coreLibraryDesugaringEnabled true"
        g = re.sub(r"compileOptions\s*\{", "compileOptions {\n        " + active, g, count=1)
        dep = 'coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")' if kts else "coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'"
        g += "\ndependencies {\n    " + dep + "\n}\n"
        gradle.write_text(g, encoding="utf-8")
        print(f"Désucrage activé : {gradle}")

# Mise à jour automatique : l'activité principale et l'installeur, dans le
# paquet que `flutter create` a choisi.
sources = Path(__file__).resolve().parent / "android"
activites = [f for f in chemin.parent.rglob("MainActivity.*") if f.suffix in (".kt", ".java")]
if activites:
    activite = activites[0]
    paquet = re.search(r"^package\s+([\w.]+)", activite.read_text(encoding="utf-8"), re.M).group(1)
    dossier = chemin.parent / "kotlin" / Path(*paquet.split("."))
    dossier.mkdir(parents=True, exist_ok=True)
    if activite.suffix == ".java":
        activite.unlink()
    for nom in ("MainActivity.kt", "MiseAJour.kt"):
        texte = (sources / nom).read_text(encoding="utf-8").replace("package PAQUET", f"package {paquet}", 1)
        (dossier / nom).write_text(texte, encoding="utf-8")
    print(f"Mise à jour automatique branchée : {dossier}")
else:
    sys.exit("MainActivity introuvable : la mise à jour automatique ne serait pas branchée.")
