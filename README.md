# دفتر الدين · Debts Book

Android app for buying from local shops on credit: log each purchase (مسواك) and payment (تسديد) per shop,
see what you owe in total, and pay a shop off in one tap. When a shop's balance reaches zero its account
moves to the archive; any overpayment stays as credit in the new account.

- The 4-digit PIN is the book: no name, no sign-up. The same PIN opens the same book on any phone
  (the book's server code is derived from it); a different PIN is a different book. A new PIN asks
  before making a book; offline it can still start one, and it merges once the internet is back.
- The app locks again after an hour in the background.
- Works with no internet: every change is saved on the phone and waits in a queue (⏳ in the top bar),
  then uploads by itself when the internet is back. The ☁️ المزامنة card shows the queue.
- Manual mode: turn off ⚡ رفع تلقائي and changes stay queued until you push them. Tap ⏳ (or 📋 المعلقة)
  to see every pending operation, then upload them one by one or all at once.
- Changes from all phones with the same PIN merge.
- Server: Supabase RPCs `debts_push` / `debts_pull` over an append-only event log (`debts_book.events`),
  addressed by a hash of the PIN. Anyone who knows (or guesses) a 4-digit PIN can open that book.

- Startup never sits on a blank screen: the splash shows at once, and if the saved data can't be read
  the app says so with a retry button. A book that can't be read is set aside, not lost.

Icon: `python3 tool/make_icon.py` draws `assets/icon.png`, the launcher mipmaps and the adaptive-icon layers.

```
flutter test
flutter build apk --release
```
