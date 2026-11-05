"""Prépare le projet Android généré par `flutter create` pour Aura.

- visible sur Android TV (leanback, pas d'écran tactile obligatoire, bannière) ;
- nom « Aura » ;
- accès réseau, y compris en http vers un Jellyfin local ;
- droit de lancer VJOD avec les liens moonfin:// (visibilité des paquets, Android 11+).

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

chemin.write_text(xml, encoding="utf-8")
print(f"Manifeste prêt : {chemin}")
