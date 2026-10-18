# دفتر الدين · Debts Book

Android app for buying from local shops on credit: log each purchase (مسواك) and payment (تسديد) per shop,
see what you owe in total, and pay a shop off in one tap. When a shop's balance reaches zero its account
moves to the archive; any overpayment stays as credit in the new account.

- Each 6-digit PIN opens its own book, so several people can keep separate books on one phone.
- 5 wrong PINs lock it for 15 minutes; the app locks again after an hour in the background.
- Works with no internet: every change is saved on the phone and waits in a queue (⏳ in the top bar),
  then uploads by itself when the internet is back. The ☁️ المزامنة card shows the queue.
- Manual mode: turn off ⚡ رفع تلقائي and changes stay queued until you push them. Tap ⏳ (or 📋 المعلقة)
  to see every pending operation, then upload them one by one or all at once.
- The book's code (in ☁️ المزامنة) opens the same book on another phone; changes from both phones merge.
- Server: Supabase RPCs `debts_push` / `debts_pull` over an append-only event log (`debts_book.events`),
  addressed by the book's random 128-bit code. The PIN never leaves the phone.

```
flutter test
flutter build apk --release
```
