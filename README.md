# iPadHilfe
iPad Hilfe Ist eine Open Source Ticketing Software für iOS und iPadOS Geräte. Die App wurde mit Unterstützung von KI in Swift entwickelt. Alle Daten werden in PocketBase gespeichert. Die App wurde dafür entwickelt, damit Nutzer von Apple Geräten intern Probleme an ihre Administratoren melden können.


Diese Repository enthält nur den Quellcode und keine prekompilierten Pakete. 

Um die app zu Kompilieren wird folgendes benötigt:
  1. Ein Mac oder Hackintosh mit mindestens macOS 15.7
  2. mindestens Xcode 26
  3. Eine pocketbase Datenbank mit dem gegebenem Scheme. Muss durch einen Cloudflare Tunnel geleitet werden

Befor sie die app Kompilieren nehmen sie bitte folgende Änderungen am Code vor:
  1. Öffnen sie die .xcodeproj Datei mit Xcode 26 oder neuer
  2. Fügen sie unter AppState.swift ihre Domain zum Cloudflare tunnel zu pocketbase ein (@AppStorage("serverURL") var serverURL: String = "https://ihre-domain.com/")
  3. Speichern sie das Projekt mit command + s

Kompilieren sie die App:
  1. Öffnen sie ein Terminal Fenster in dem Ordner in welchem sich die .xcodeproj Datei befindet
  2. Führen sie diesen Befehl aus:
<code> xcodebuild clean build -scheme "iPad Hilfe" -sdk iphoneos -configuration Release CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO </code>
  4. über ** BUILD SUCCEEDED ** wird der Pfad der neu kompilierten Datei angezeigt er sollte so aussehen: <code> /Users/Ihr-Nutzername/Library/Developer/Xcode/DerivedData/Projekt-name-zufälliger-string/Build/Products/Release-iphoneos/ </code> Kopieren sie diesen und öffnen sie Finder
  5. Drücken sie Shift + command + g und fügen sie den Pfad ein
  6. Kopieren sie die .app Datei auf ihren Desktop
  7. erstellen sie einen neuen Ordner namens 'Payload' auf ihrem desktop und verschieben sie die .app Datei hinein
  8. Erstellen sie ein zip Archiv aus dem Ordner und benennen sie die Datei 'Payload.zip' zu 'Payload.ipa' um

Installieren sie jetzt die App mit dem Sideloader ihres Vertrauens (empfohlen: Altstore classic ; iLoader ; Sideloadly)
