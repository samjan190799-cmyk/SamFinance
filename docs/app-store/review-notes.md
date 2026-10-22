# Заметки для проверяющего (App Review Information → Notes)

Где вставить: App Store Connect → версия приложения → **App Review Information** → поле **Notes**. Сам текст ниже написан по-английски: проверяющие читают его. Поле принимает до 4000 знаков, здесь около 3000.

В поле **Sign-In Information** галочку «Sign-in required» не ставьте: входа нет. В **Contact Information** укажите своё имя, телефон и почту (они видны только Apple).

## Текст для вставки

```text
Hashiv is a personal finance tracker for iPhone: transactions, cards, debts, savings goals and reports. There are no accounts, no sign-in, no subscriptions and no in-app purchases, so no demo account is needed. All data is stored on the device; the developer has no server.

HOW TO TRY IT (no setup required)
1. Overview tab, "+" button: add an expense or income. Cards tab, "+" button: add a card (any test number, for example 4111 1111 1111 1111; the CVV is never requested or stored). On the Cards tab, "Edit" opens the card editor and "All goals" opens the savings goals; Overview also has a "Goals" block.
2. SMS recognition. iOS does not let apps read SMS, so the app works with text the user copies. Copy this sample bank SMS (typical for Armenian banks), then on the Overview tab tap the clipboard icon at the top right and tap "Add" on the banner "SMS found in clipboard". A transaction, a card ending 0640 and its balance are created automatically. The same text can also be pasted into the "AI" tab.

GNUM
3,500.00 AMD
4318***0640
SAS SUPERMARKET, AM
15.01.2025 14:32
MNACORD 120,000.00

Recognition runs on the device. The same works with screenshots of such SMS (the "AI" tab, photo button): text is recognized on the device with Apple's Vision framework.
3. "AI" tab without a key: a local assistant answers questions from the data on the phone, for example "what is my balance?", "how are my goals?", "how much did I spend this week?" (it understands Russian, English and Armenian).

OPTIONAL CLOUD AI
In Settings > AI assistant the user may paste their OWN API key of Claude (Anthropic), ChatGPT (OpenAI) or Gemini (Google). We provide no keys and sell no AI access, so this part cannot be tried without a personal key and is off by default. Before the first request the app shows a consent dialog that says exactly what is sent and to whom (question, screenshots, a summary of transactions, cards with the last 4 digits only, and debts). Deleting the key withdraws the consent. Full card numbers, CVV and cardholder names are never sent.

PERMISSIONS AND NETWORK
- Notifications only (optional): reminders for debt due dates and prompts after Apple Pay purchases.
- Photos are chosen in the system picker; the clipboard is read only when the user taps a scan or paste button. No location, camera, microphone, contacts or tracking.
- Network: exchange rates from open.er-api.com (no user data) and the AI provider the user chose, only after they add a key and give consent. Encryption is limited to standard HTTPS (ITSAppUsesNonExemptEncryption = NO).

OTHER
- Languages: Russian, English and Armenian. Armenian is not an iOS system language, so it is chosen in Settings > Language and applies after a restart.
- Privacy policy: Settings > Privacy policy (inside the app) and the URL in the metadata. All data can be erased in Settings > Reset All Data.
- Hashiv is not a bank, does not move money and does not give financial advice.
```

## Что это значит для вас

- Проверяющему не нужны ни аккаунт, ни ключ ИИ: всё основное проверяется без настройки. Это главное, ради чего написаны заметки.
- Если проверяющий захочет увидеть облачного ИИ, он поймёт из заметок, что приложение не выдаёт ключи. Если Apple всё же попросит показать эту часть, можно приложить короткое видео, где вы вставляете свой ключ и задаёте вопрос.
- Названия кнопок в тексте даны по английскому интерфейсу (проверяющие обычно открывают приложение на английском). Если подписи на экране поменяются, поправьте и текст.
- Ссылка на политику конфиденциальности должна работать до отправки на проверку. См. `docs/app-store/README.md`.
