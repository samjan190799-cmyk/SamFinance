# Ответы для App Privacy (App Store Connect)

Где заполнять: App Store Connect → ваше приложение → **App Privacy** → Get Started / Edit. Названия пунктов даны так, как они в анкете Apple (по-английски). Ответы совпадают с `Resources/PrivacyInfo.xcprivacy` и с политикой конфиденциальности.

## Почему «да, данные собираются»

Своего сервера у Hashiv нет, и разработчик не видит данные пользователя. Но по правилам Apple передача данных за пределы устройства сторонней компании считается сбором. Если пользователь разрешил отправку, ИИ-помощник отправляет его вопросы, скриншоты, сводку учёта и итоги расчётов по истории в Anthropic, OpenAI или Google (запросы идут с ключом разработчика, встроенным в сборку). Поэтому честнее и безопаснее ответить «да» и указать эти типы данных. Лишнее объявление не повод для отказа, а недостающее — повод.

## Анкета

| Вопрос | Ответ |
| --- | --- |
| Do you or your third-party partners collect data from this app? | **Yes** |

### Типы данных

Выберите ровно эти шесть типов: три про работу приложения и три про рекламу Яндекса (ответы для рекламы в отдельной таблице ниже).

| Категория | Тип | Что это в Hashiv |
| --- | --- | --- |
| Financial Info | **Other Financial Info** | балансы карт и операции в сводке для ИИ |
| Photos or Videos | **Photos or Videos** | скриншоты, которые пользователь прикладывает в ИИ-чат |
| User Content | **Other User Content** | вопросы к ИИ и история чата, заметки, имена в долгах, названия копилок и напоминаний |
| Identifiers | **Device ID** | идентификаторы устройства и рекламный идентификатор для рекламы Яндекса |
| Usage Data | **Advertising Data** | сведения о показах и нажатиях на рекламу |
| Usage Data | **Product Interaction** | взаимодействие с рекламой (показы, нажатия) |

Для первых трёх типов (работа приложения):

| Вопрос | Ответ |
| --- | --- |
| Is this data linked to the user's identity? | **No** (аккаунтов и идентификаторов нет) |
| Do you or your third-party partners use this data for tracking purposes? | **No** |
| Purposes | **App Functionality** (только он) |

Для трёх типов про рекламу (Device ID, Advertising Data, Product Interaction):

| Вопрос | Ответ |
| --- | --- |
| Is this data linked to the user's identity? | **Yes** (рекламный идентификатор и идентификаторы устройства связывают показы с устройством) |
| Do you or your third-party partners use this data for tracking purposes? | **Yes** |
| Purposes | **Third-Party Advertising** (только он) |

### Что не выбирать

Не отмечайте: Contact Info, Health & Fitness, Payment Info (полный номер карты никуда не отправляется), Credit Info, Location, Sensitive Info, Contacts, Browsing History, Search History, Purchases, Other Data. Из Identifiers отметьте только Device ID, из Usage Data только Advertising Data и Product Interaction (ради рекламы). Из Diagnostics ничего: отчётов о сбоях от разработчика в приложении нет. Яндекс Реклама тянет за собой AppMetrica, у которой есть собственный манифест приватности; если App Store Connect или отчёт о приватности (Privacy Report в Xcode) покажет другие типы данных, отметьте и их.

Запрос курсов валют к open.er-api.com не содержит данных пользователя, поэтому отдельного пункта не требует.

## Остальные поля App Store Connect, связанные с приватностью

| Поле | Что указать |
| --- | --- |
| Privacy Policy URL | ссылка на страницу политики (см. `docs/app-store/README.md`, раздел «Публикация политики») |
| Support URL | обязательна; нужна страница, где можно связаться с вами (почта или форма) |
| Tracking (App Tracking Transparency) | **используется**: запрос «Разрешить отслеживание» показывается перед первой рекламой (`NSUserTrackingUsageDescription` в `Info.plist`, переводы в `InfoPlist.strings`); в `PrivacyInfo.xcprivacy` стоит `NSPrivacyTracking = true` и перечислены домены отслеживания AppMetrica (при `true` пустой список Apple отклоняет: ITMS-91064) |
| Advertising Identifier (IDFA) | **Yes**: только «Serve advertisements within the app»; два других пункта (атрибуция установок и действий) **No** |
| Encryption | в `Info.plist` стоит `ITSAppUsesNonExemptEncryption = NO` (только системный HTTPS), поэтому вопрос об экспорте шифрования не задаётся при каждой сборке |
| Sign-in required | **No**, демо-аккаунт не нужен |
| Content Rights | сторонний контент не используется |
| Digital Services Act (ЕС) | если приложение будет доступно в ЕС, Apple попросит указать статус «trader» или «non-trader»; решение за вами |

## Возрастной рейтинг

Анкета Apple периодически меняется, поэтому сверяйтесь с экраном. Ожидаемые ответы: насилие, азартные игры, контент для взрослых, алкоголь, табак, медицинские советы — **None / No**. Если есть вопрос про чат-бота или ИИ-контент, ответьте **Yes**: чат использует внешние модели и приложение не модерирует их ответы. Свободного доступа в интернет (веб-браузера) в приложении нет. Категория: **Finance**.

## Если что-то изменится

Для рекламы Яндекса отдельно: пока `NSPrivacyTracking = true`, список `NSPrivacyTrackingDomains` в `PrivacyInfo.xcprivacy` не может быть пустым (ITMS-91064, сборка получает «Ошибку двоичного файла»). Сейчас там два домена из манифеста AppMetrica (`AppMetricaAdSupport`); при обновлении SDK сверьте список с его манифестом. Если реклама уйдёт, уберите оба ключа сразу. Любой новый вид отправки данных (аналитика, свой сервер, облачная синхронизация, подписка) нужно сначала отразить в `PrivacyInfo.xcprivacy`, политике (`Resources/Legal`) и в этой анкете, и только потом выпускать.
