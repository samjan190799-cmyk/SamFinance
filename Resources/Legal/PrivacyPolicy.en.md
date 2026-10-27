# Hashiv Privacy Policy

Effective October 22, 2026.

## In short

- Hashiv keeps your data only on your iPhone. The app has no accounts and no server of ours: we do not receive or see your transactions, cards, debts or savings goals.
- The app has no ads, analytics, tracking or third-party SDKs.
- The only things that leave your phone are exchange-rate requests (without your data) and, if you turn on the AI assistant yourself, your requests to the AI service you chose.
- You can erase all your data in Settings.

## Who we are

Hashiv is developed by an independent developer ("we"). You can ask privacy questions through the "Support" link on the Hashiv page in the App Store.

## What the app stores

Everything listed here stays on your device. We have no access to it.

- **Transactions:** title, amount, category, date, note.
- **Cards:** purpose, cardholder name, expiry date, last 4 digits, balance, bank and design. The full card number is saved only if you enter it yourself, and it lives in this device's secure iOS storage (Keychain). The app never asks for or stores the CVV code.
- **Debts and loans:** name of a person or bank, amount, due date.
- **Savings goals:** name, target, deadline, log of deposits and withdrawals.
- **Reminders:** text, date and time, repeat, note.
- **Settings:** language, currency, chosen AI service, automation rules (remembered merchant categories, your surname used to recognize transfers to yourself).
- **AI keys:** a key you paste is kept in this device's Keychain and does not move to other devices.

Data files are protected by iOS and open only while the phone is unlocked. They may be included in iPhone backups that you make yourself (iCloud or a computer). Keychain items are not part of backups.

## What leaves your phone

**1. Exchange rates.** On launch the app requests currency rates from the open service open.er-api.com. The request contains none of your data, but like any website the service sees the IP address of your connection.

**2. AI assistant (optional).** It works only if you add your own Claude (Anthropic), ChatGPT (OpenAI) or Gemini (Google) key and allow data sharing before the first request. Then the chosen service receives:

- your question and the recent messages of the conversation;
- screenshots you attach (receipts, statements, bank apps) and the text recognized on them on your phone;
- a summary of your records: cards (purpose, last 4 digits, balance), spending and income for 30 days by category, up to 60 latest transactions (date, amount, title, category, card), debts (name, amount, due date, reminder), savings goals (name, target, amount saved, deadline), your own reminders (text, date, repeat), the current date, language and currency.

Not sent: full card numbers, CVV and cardholder names. Bank SMS that the app recognizes on the phone never go to the cloud. The key is used only to sign in to the chosen service.

Requests go straight from your phone to the chosen service using your key. Our server is not part of this chain and we receive no copies. The service processes data under its own rules, possibly in another country: [Anthropic](https://www.anthropic.com/legal/privacy), [OpenAI](https://openai.com/policies/privacy-policy), [Google](https://policies.google.com/privacy). Requests are billed to your key.

If you ask the AI to change something in the app (add a debt, set a reminder), it only proposes the changes as a card in the chat. The app makes them only when you tap "Apply".

You can withdraw permission at any time: delete the key in Settings → AI assistant. Without a key the app answers questions using only the data on your phone.

**3. iOS features.** You choose screenshots in the system iOS picker, and the app sees only the pictures you pick. The clipboard is read only when you tap the buttons that scan an SMS or paste from the clipboard. Export puts a CSV table on the clipboard when you tap it. Reminders (about debts, savings goals, cards and your own) and Apple Pay purchase prompts are shown by the device itself if you allowed notifications. Shortcuts run on your phone; the app does not read messages on its own, iOS does not allow that.

## What we do not do

- we do not create accounts or collect contact details;
- we do not show ads or pass data to ad networks;
- we do not use analytics, tracking or third-party SDKs;
- we do not sell or share your data with third parties, except as described above when you connect an AI service yourself.

## Your control

- **Delete data:** Settings → "Reset All Data" erases transactions, cards, debts, savings goals and saved card numbers. The AI key is removed separately: Settings → AI assistant → "Delete key".
- **Delete the app:** the data files are removed with it. iOS may keep Keychain items, so do both actions above before deleting.
- **Take your data:** Settings → "Export Data" copies transactions as CSV.
- **Withdraw AI consent:** delete the key as described above.

## Children

Hashiv is not intended for children under 13. We do not collect data about anyone, including children.

## Security

Data is protected by iOS: file protection, Keychain and an encrypted connection (HTTPS) for every network request. No system is 100% secure, so do not send an AI service anything you are not ready to share, and keep your phone locked with a passcode.

## Good to know

Hashiv is a tracking tool, not a bank or a financial advisor. AI answers can be inaccurate: check the amounts and do not treat them as investment, tax or credit advice.

## Changes

If this policy changes, we will update the date above and this text in a new version of the app.

## Contact

Privacy questions: the "Support" link on the Hashiv page in the App Store.
