# D. Voce

Un'app Android che trasforma i tuoi **PDF, EPUB e file di testo in audiolibri**,
con voci naturali che funzionano **tutto offline**: la voce gira direttamente
sul telefono, senza account, senza abbonamenti e senza mandare i tuoi libri
da nessuna parte.

Le voci si basano su [Supertonic 3](https://github.com/supertone-inc/supertonic)
e [Piper](https://github.com/OHF-Voice/piper1-gpl), tramite
[sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx).

## Novità v0.2 – audiolibri

- **Libreria**: aggiungi libri PDF, EPUB o TXT (oppure incolla un testo).
- **Capitoli automatici**: dall'indice del PDF o dell'EPUB, oppure dai titoli
  "Capitolo 1", "Parte seconda", "IV"… Se non ce ne sono, il libro viene
  diviso in parti da circa mezz'ora.
- **Pulizia dei PDF**: via numeri di pagina e intestazioni ripetute, parole
  spezzate dal trattino ricucite, paragrafi ricomposti.
- **10 voci naturali** (5 femminili, 5 maschili) in un unico download da 129 MB,
  che leggono anche in altre 30 lingue (inglese, spagnolo, francese, tedesco…).
- **Italiano letto bene**: numeri, date, prezzi, orari, percentuali,
  abbreviazioni (dott., pag., ecc.) e capitoli in numeri romani vengono letti
  per esteso.
- **Segnalibro automatico**: ogni libro riparte dalla frase dove eri rimasto.
- Velocità da 0,75× a 2×, **timer di spegnimento** (minuti o fine capitolo),
  frase e capitolo precedente/successivo.
- **Ascolto a schermo spento** con i comandi nella notifica, nella schermata
  di blocco e sulle cuffie.

## Limiti noti

- I PDF fatti di immagini (pagine fotografate o scansionate) non contengono
  testo e non si possono leggere.
- Tabelle, note a piè di pagina e impaginazioni a più colonne possono uscire
  in ordine strano.
- La voce viene preparata frase per frase sul telefono: sui telefoni meno
  potenti può esserci una breve pausa tra una frase e l'altra. In quel caso
  usa la qualità "Normale" o una voce leggera.
- Le voci leggere (Paola, Riccardo) leggono solo in italiano.
- Non legge i file protetti da DRM (ad esempio molti ebook comprati online).

## Come si installa

Scarica l'APK dall'ultima [release](../../releases/latest)
(`app-arm64-v8a-release.apk`), aprilo e consenti l'installazione.

## Sviluppo

Le cartelle `android/` e `ios/` non sono nel repository: le crea
`tool/setup_platforms.sh` durante la build su GitHub Actions. La CI prova
anche le voci vere (estrazione, sintesi e campioni audio allegati alla release).

Licenza: GPL-3.0 (richiesta dalla libreria espeak-ng usata per la pronuncia
delle voci Piper). Il carattere Sora è distribuito con licenza SIL OFL
(`assets/fonts/OFL.txt`).

---
un'app Dom Studio
