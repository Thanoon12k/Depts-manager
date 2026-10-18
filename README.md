# دفتر الدين · Debts Book

Android app for buying from local shops on credit: log each purchase (مسواك) and payment (تسديد) per shop,
see what you owe in total, and pay a shop off in one tap. When a shop's balance reaches zero its account
moves to the archive; any overpayment stays as credit in the new account.

- Each 6-digit PIN opens its own book, so several people can keep separate books on one phone.
- 5 wrong PINs lock it for 15 minutes; the app locks again after an hour in the background.
- Everything stays on the phone (no account, no internet).

```
flutter test
flutter build apk --release
```
