# PurlLab 🧶

> **Smart Knitting Companion for iOS & watchOS**  
> Trasforma i tuoi pattern PDF in guide interattive passo-passo, ricalcola il campione su misura con l'AI e sincronizza i tuoi progressi in tempo reale con Apple Watch.

[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg?style=flat-square&logo=swift)](https://swift.org)
[![iOS](https://img.shields.io/badge/iOS-18.0%2B-blue.svg?style=flat-square&logo=apple)](https://developer.apple.com/ios/)
[![watchOS](https://img.shields.io/badge/watchOS-11.0%2B-silver.svg?style=flat-square&logo=apple)](https://developer.apple.com/watchos/)
[![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-purple.svg?style=flat-square)](https://developer.apple.com/xcode/swiftui/)
[![SwiftData](https://img.shields.io/badge/Storage-SwiftData-green.svg?style=flat-square)](https://developer.apple.com/documentation/swiftdata)
[![Gemini](https://img.shields.io/badge/AI-Google%20Gemini-4285F4.svg?style=flat-square&logo=google)](https://aistudio.google.com/)

---

## 🌟 Panoramica

**PurlLab** è un'applicazione nativa moderna progettata specificamente per chi lavora a maglia. Risolve le complessità dei pattern tradizionali su carta o PDF, trasformandoli in schede di lavoro intuitive e interattive, con contatori sincronizzati istantaneamente tra iPhone e Apple Watch.

---

## ✨ Funzionalità Principali

### 🤖 Analisi Intelligente dei Pattern (Google Gemini AI)
- Importa direttamente pattern da file **PDF**.
- L'intelligenza artificiale (**Gemini 2.5 Flash** con fallback a **Gemini 3.x**) analizza il documento, estrae le sezioni, le istruzioni riga per riga, i ferri da lavorare e genera una guida ordinata e strutturata.
- Gestione guidata degli **schemi a quadretti (chart)**: senso di lettura, colonna di partenza e contatori dedicati.

### 📐 Ricalcolo del Campione (Gauge Recalculation)
- Il tuo campione di tensione è diverso da quello raccomandato dal designer?
- Inserisci le tue maglie e righe su 10 cm: PurlLab ricalcola matematicamente le maglie da avviare, gli aumenti e le diminuzioni per la tua taglia, mantenendo inalterata la vestibilità del capo originale.

### 🔢 Contatori Interattivi & Statistiche
- **Contatori di sezione e globali**: tieni traccia del ferro corrente, delle ripetizioni e del target da raggiungere.
- **Visualizzazione maglie sul ferro**: differenziale automatico (es. `5 → 25 m (+20)`).
- **Contatori secondari personalizzati**: ripetizioni di trecce, coste, aumenti raglan.
- Spunta visiva automatica al completamento delle sezioni e statistiche cumulative (totale maglie e ferri lavorati).

### ⌚ Apple Watch Companion App
- **Sincronizzazione bidirezionale in tempo reale** via `WatchConnectivity`.
- **Supporto Digital Crown**: incrementa e decrementa il contatore ruotando la corona digitale con protezione intelligente anti-rimbalzo (debouncing).
- **Feedback aptico**: vibrazioni distinte per ogni ferro avanzato (`.click`) e per il raggiungimento del target (`.success`).
- **Cronometro di sessione live**: visualizzazione in tempo reale al secondo (`TimelineView`) con stato attivo evidenziato.
- **Cache offline e resilienza**: i comandi inviati a orologio spento o scollegato vengono accodati e sincronizzati automaticamente non appena la connessione torna disponibile.
- **Schermo sempre attivo**: display sempre acceso durante la lavorazione (`isIdleTimerDisabled` su iPhone e sessione estesa su watchOS).

### ⏱️ Sessioni e Cronometro Integrato
- Timer intelligente per monitorare il tempo dedicato a ciascun progetto.
- **Auto-pausa automatica** in caso di inattività per non falsare le metriche.
- Storico e analytics delle sessioni salvati localmente.

### 🔒 Sicurezza e Privacy by Design
- **Nessuna registrazione account o cloud proprietario**: tutti i progetti, le note e le statistiche sono memorizzati in locale tramite **SwiftData** (`PurlLabV4`).
- **Chiave API protetta**: la chiave API personale di Gemini viene inserita nelle Impostazioni e archiviata in modo sicuro nel **Keychain hardware di Apple** (`kSecClassGenericPassword`). Nessuna credenziale è salvata in chiaro o inclusa nel codice sorgente.

---

## 🛠️ Architettura e Stack Tecnologico

- **Linguaggio**: Swift 6.0 (Strict Concurrency ready)
- **Framework UI**: SwiftUI (NavigationStack, TimelineView, matchedGeometryEffect)
- **Persistenza**: SwiftData con supporto a migrazioni e contenitore temporaneo di emergenza
- **Connettività Watch**: `WatchConnectivityIOSManager` e `WatchCommandCoordinator` con architettura a stati protetti, deduplicazione dei comandi tramite UUID in UserDefaults e fallback su `transferUserInfo`
- **Integrazione AI**: Client REST nativo per Google Gemini API con timeout adattivo e retry con backoff
- **PDF Kit**: Rendering e visualizzazione integrata dei PDF originali

---

## 🚀 Prerequisiti e Avvio Rapido

### Requisiti
- **Xcode 16.0+**
- **iOS 18.0+**
- **watchOS 11.0+**
- Chiave API gratuita [Google AI Studio](https://aistudio.google.com/)

### Installazione
1. Clona il repository:
   ```bash
   git clone https://github.com/chiarafragomeli/PurlLab.git
   cd PurlLab
   ```

2. Apri il progetto in Xcode:
   ```bash
   open PurlLab.xcodeproj
   ```

3. Seleziona il tuo **Team di Sviluppo** in *Signing & Capabilities* per i target `PurlLab` e `PurlLabWatch`.

4. Collega il tuo iPhone / Apple Watch (o avvia il Simulatore) e premi **Run** (`⌘R`).

5. Nell'app, apri la scheda **Impostazioni**, inserisci la tua chiave API di Gemini e premi **Verifica Connessione**.

---

## 🧪 Test Unitari

Il progetto include una suite completa di test unitari che copre logica di dominio, deduplicazione comandi, timer, persistenza e sincronizzazione Watch:

```bash
xcodebuild test -scheme PurlLab -destination 'platform=iOS Simulator,name=iPhone 17'
```

---

## 📂 Struttura del Repository

```
PurlLab/
├── App/                # Ciclo di vita applicazione e configurazione container
├── Models/             # Modelli di dominio SwiftData e WatchProjectSummary
├── Services/           # GeminiService, KeychainHelper, TimerManager, WatchConnectivity
├── Views/              # Viste SwiftUI (Progetti, Guida, Contatori, PDF, Impostazioni)
└── Resources/          # Asset, icone, pattern di riferimento
PurlLabWatch/
├── Models/             # Modelli sincronizzati per watchOS
├── Services/           # WatchConnectivityManager e WatchCommandCoordinator
└── Views/              # WatchCounterView, WatchProjectListView
PurlLabTests/           # Suite di test unitari automatizzati
```

---

## 👤 Autore

**Chiara Fragomeli**  
GitHub: [@chiarafragomeli](https://github.com/chiarafragomeli)
