# D. Voce

Un'app Android che legge ad alta voce i tuoi testi con voci italiane naturali,
**tutto offline**: la voce gira direttamente sul telefono, senza account,
senza abbonamenti e senza mandare il testo da nessuna parte.

Si basa su [Piper](https://github.com/OHF-Voice/piper1-gpl) (voci neurali)
tramite [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) e
[piper-phonemize](https://github.com/csukuangfj/piper-phonemize).

## Funzioni (v0.1)

- Scrivi, incolla o apri un file `.txt` e premi **Ascolta**.
- Due voci italiane da scaricare una volta sola:
  - **Paola** – femminile, qualità media (67 MB)
  - **Riccardo** – maschile, qualità base, più leggera (26 MB)
- Velocità regolabile da 0,6× a 1,6×.
- Pausa, frase precedente/successiva, cursore per saltare a un punto.
- **Salva audio**: crea un file WAV con tutta la lettura e lo condividi
  (WhatsApp, Drive, email…).
- Il testo resta salvato quando chiudi l'app.

## Limiti noti

- Niente PDF ed ebook per ora (solo testo e `.txt`).
- Con lo schermo spento o l'app in background Android può interrompere la lettura.
- Le voci Piper sono buone ma non perfette: a volte sbagliano un accento,
  soprattutto su nomi propri, sigle e parole straniere.
- I file WAV sono grandi (circa 2,5 MB al minuto con Paola).

## Come si installa

Scarica l'APK dall'ultima [release](../../releases/latest)
(`app-arm64-v8a-release.apk`), aprilo e consenti l'installazione.

## Sviluppo

Le cartelle `android/` e `ios/` non sono nel repository: le crea
`tool/setup_platforms.sh` durante la build su GitHub Actions.

Licenza: GPL-3.0 (richiesta dalla libreria espeak-ng usata per la pronuncia).
Il carattere Sora è distribuito con licenza SIL OFL (`assets/fonts/OFL.txt`).

---
un'app Dom Studio
