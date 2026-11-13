# Заметки для проверяющего (App Review Information → Notes)

Где вставить: App Store Connect → версия приложения → **App Review Information** → поле **Notes**. Сам текст ниже написан по-английски: проверяющие читают его. Поле принимает до 4000 знаков, при правках проверяйте длину (сейчас текст ниже около 4000: если не влезает, сократите абзацы про рекламу и разрешения).

В поле **Sign-In Information** галочку «Sign-in required» не ставьте: входа нет. В **Contact Information** укажите своё имя, телефон и почту (они видны только Apple).

## Текст для вставки

```text
Hashiv is a personal finance tracker for iPhone: transactions, cards, debts, savings goals and reports. There are no accounts, no sign-in, no subscriptions and no in-app purchases, so no demo account is needed. All data is stored on the device; the developer has no server.

HOW TO TRY IT (no setup required)
1. Overview tab, "+" button: add an expense or income. Cards tab, "+" button: add a card (any test number, for example 4111 1111 1111 1111; the CVV is never requested or stored). On the Cards tab, "Edit" opens the card editor and "All goals" opens the savings goals; Overview also has a "Goals" block.
2. SMS recognition. iOS does not let apps read SMS, so the app works with text the user copies. Copy this sample bank SMS (typical for Armenian banks), then on the Overview tab tap "From SMS" under the balance card and tap "Add" on the banner "SMS found in clipboard". A transaction, a card ending 0640 and its balance are created automatically. The same text can also be pasted into the "AI" tab.

GNUM
3,500.00 AMD
4318***0640
SAS SUPERMARKET, AM
15.01.2025 14:32
MNACORD 120,000.00

Recognition runs on the device. The same works with screenshots of such SMS (the "AI" tab, photo button): text is recognized on the device with Apple's Vision framework.
3. "AI" tab: bank SMS text and screenshots are recognized on the device. Other questions, for example "what is my balance?", "how are my goals?", "how much did I spend this week?", go to the cloud AI after the user allows it in the consent dialog (see CLOUD AI
The assistant works out of the box with an API key that belongs to the developer and is built into the build (users enter no key and pay nothing). The only cloud AI service is Google Gemini, named in the consent dialog; the app does not use ChatGPT or OpenAI and cannot be switched to them (guideline 5, China). Before the first request a consent dialog says exactly what is sent and to whom (question, screenshots, a summary of transactions, cards with the last 4 digits only, debts, goals and reminders, and, when a question needs older data, on-device totals and up to 25 transactions per query). The AI can propose changes (for example add a debt); nothing changes until the user taps "Apply" in the chat. The switch "Send data to AI" in Settings > AI assistant withdraws the consent. Full card numbers, CVV and cardholder names are never sent.

ADVERTISING
Each of the five tabs shows its own Yandex Mobile Ads banner (Yandex Advertising Network) inside the scrolling content, between the first and second blocks of the screen (on Overview, between the balance card and the quick-action buttons); it scrolls with the content and loads a new ad when the tab is opened. It is a separate strip above the screen content and never covers an input field or a button. Before the first ad iOS shows the App Tracking Transparency prompt (the usage description is localized in Russian, English and Armenian); declining does not disable ads, they are just less personalized. No transactions, cards, debts or other financial data are ever passed to the ad SDK. Builds without an ad unit id contain no ads at all.

PERMISSIONS AND NETWORK
- Notifications only (optional): reminders for debt due dates and prompts after Apple Pay purchases.
- Photos are chosen in the system picker; the clipboard is read only when the user taps a scan or paste button. No location, camera, microphone, contacts or tracking.
- Network: exchange rates from open.er-api.com (no user data) and the AI service named in the consent dialog (Google Gemini), only after the user gives consent. Encryption is limited to standard HTTPS (ITSAppUsesNonExemptEncryption = NO).

OTHER
- Languages: Russian, English and Armenian. Armenian is not an iOS system language, so it is chosen in Settings > Language and applies after a restart.
- Privacy policy: Settings > Privacy policy (inside the app) and the URL in the metadata. All data can be erased in Settings > Reset All Data.
- Hashiv is not a bank, does not move money and does not give financial advice.
```

## Что это значит для вас

- Проверяющему не нужны ни аккаунт, ни ключ ИИ: всё основное проверяется без настройки. Это главное, ради чего написаны заметки.
- Облачный ИИ работает по ключу сборки (Google Gemini). Слова ChatGPT и OpenAI ни в карточке, ни в этих заметках, кроме одной фразы про Китай, не используйте: 12 ноября 2026 Apple отклонила версию 1.1.0 по Guideline 5 (Китай) именно из-за них.
- Названия кнопок в тексте даны по английскому интерфейсу (проверяющие обычно открывают приложение на английском). Если подписи на экране поменяются, поправьте и текст.
- Ссылка на политику конфиденциальности должна работать до отправки на проверку. См. `docs/app-store/README.md`.
