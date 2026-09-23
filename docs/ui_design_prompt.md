# Design brief: Mindfull mobile app UI

You are a senior mobile product designer. Design the complete UI for **Mindfull**, a private health and wellness journal for iOS and Android. Read the whole brief before you start. Design only what is described here. Do not add features, such as accounts, social sharing, cloud sync, streaks or gamification.

---

## 1. What the app is

Mindfull is a journal where people log their **mood, symptoms, medication, sleep and notes** (typed or dictated). A small AI language model runs **entirely on the phone**. It reads the journal and answers questions such as "When did my headaches start getting worse?" or "Summarise my week for my doctor". It can also do simple actions, like setting a medication reminder, after the user approves them.

**The core promise: no health data ever leaves the phone.** The app works in airplane mode. There is no account, no server and no analytics on what users write.

### Who uses it
- People tracking chronic conditions (migraine, diabetes, anxiety) who don't trust cloud AI with health data.
- People who want a clear summary to show their doctor, instead of scrolling through notes.
- Typical user: 25–60 years old. They may feel unwell when they use the app (for example during a migraine: light-sensitive, low energy, one-handed). Logging must take **under 20 seconds**.

### How it should feel
- **Calm, private, trustworthy, warm.** Think of a well-made paper journal crossed with a quiet, capable assistant.
- **Not clinical.** No hospital blues, stethoscopes, pills-and-crosses clip art, or charts that look like lab results.
- **Not gamified.** No streaks, badges, confetti, or guilt ("You missed 3 days!").
- Privacy should be **visible but not alarming**. Present it as reassurance, not as a security warning.

---

## 2. Platform and technical constraints

- Built in **Flutter** with Material 3 widgets. Custom styling is fine, but every component must be realistic to build in Flutter. Avoid effects that depend on platform-only APIs.
- One design for both iOS and Android. It must feel at home on both. Respect safe areas, the iOS home indicator and Android gesture navigation.
- Design frames: **iPhone 390×844** (primary) and **Android 412×915**.
- **Light and dark mode** are both required. Dark mode matters, because people with migraines use the app in dark rooms.
- **Accessibility (required):**
  - WCAG AA contrast in both themes.
  - Tap targets of at least 44×44 pt.
  - Layouts must survive text scaled up to 200% (Dynamic Type / font scale).
  - **Mood must never be shown by colour alone.** Always pair it with an icon/face and a label.
  - Avoid a red↔green scale, for colour-blind users.
- Navigation is a **bottom navigation bar with 3 tabs: Journal, Ask, Settings.** Full-screen flows, such as the entry editor, open above the tab bar.

---

## 3. Data the user logs (one entry)

| Field | Details |
|---|---|
| Date & time | Defaults to now. Can be changed (backdating allowed). |
| Mood | **Required.** 5 levels: 1 Very low, 2 Low, 3 Okay, 4 Good, 5 Great. |
| Symptoms | Zero or more free-text tags (e.g. Migraine, Nausea, Fatigue). Suggestions come from the user's own history plus starter tags. |
| Medications taken | Zero or more free-text tags (e.g. "Sumatriptan 50mg"). |
| Sleep last night | Optional. 0–14 hours in 0.5 h steps. |
| Notes | Free text, which can be dictated by voice. Speech is recognised on the device, and the user edits the transcript before saving. |
| Voice flag | The entry shows a small mic marker if it was dictated. |

---

## 4. Screens to design

For every screen, show these states where relevant: **populated, empty, loading, error.** Show the AI screens in each of their model states too.

### A. Onboarding (first run)
1. **Welcome / privacy promise.** App name, a one-line purpose, and 3 short points: *Stays on your phone* · *Works offline* · *Lock it with a PIN or Face ID*. There is a **required checkbox**: "I understand Mindfull is a wellness journal, not medical advice." **Get started** stays disabled until it is ticked.
2. **Device check & model recommendation.** The app checks RAM and free storage, then recommends an AI model:
   - A capable phone gets the larger model (~1.5–3 GB).
   - A budget phone gets a small model (~0.5 GB).
   - A phone that is too weak has AI switched off cleanly. The journal still works.
   Show model name, download size, a speed estimate, and "Skip for now". Make it clear the journal works without the model.
3. **Model download.** Progress bar with MB / total, pause and resume, a warning when on mobile data, a storage check before starting, and a checksum "Verifying…" step. The user can leave this screen and keep journaling while it downloads.

### B. Journal tab (home / timeline)
- **App bar:** title, a small **"Network: Off" pill** (cloud-off icon, always visible; it turns "On" only during a model download), and a filter button with a dot when filters are active.
- **Weekly insight card** (AI-generated when the model is ready; e.g. "Poor sleep came before 3 of 4 migraines this week"). Provide a non-AI fallback.
- **Stats + chart card** for the selected range (default: last 30 days):
  - Entry count, average mood, average sleep.
  - A line chart of daily average mood, with gaps on days with no entries.
  - "Most logged symptoms" chips with counts.
- **Entry list** grouped by day ("Today", "Yesterday", "Monday, 21 September"). Each entry card shows the time, mood face and label, sleep hours, a 2-line preview of the note, symptom chips, medication chips (visually different from symptoms), and a mic marker if dictated. Tapping a card opens it for editing.
- **Active filter chips** row under the app bar (removable), plus "Clear all".
- **Primary action:** a prominent **"New entry"** button, reachable with the thumb.
- **Empty states:** (a) the journal is empty, with a gentle invitation to log; (b) no entries match the filters, with a hint to widen them.

### C. Filter sheet (bottom sheet)
- Date: All time · 7 days · 30 days · 90 days · Custom range.
- Mood range: a two-handle slider from Very low to Great.
- Symptoms and Medications: selectable chips from the user's history.
- Footer: Reset · **Show entries**.

### D. New / Edit entry (full screen)
- Top bar: Close, title ("New entry" / "Edit entry"), **Save**. In edit mode, add Delete.
- Order: date-time chip → **"How are you feeling?"** mood picker (5 large faces with labels) → Symptoms tag picker → Medications tag picker → Sleep (a "Log sleep" button that expands into a slider showing "7.5 h", removable) → Notes (multi-line) with a **mic button**.
- **Tag picker:** selected tags as removable chips, a text field to add a new tag, and quick-add suggestion chips.
- **Voice dictation state:** clearly show "Listening on-device…" and a stop control. The transcript appears live in the notes field and can be edited.
- **Validation:** mood is the only required field. Save without a mood shows a short, gentle message.
- **Dialogs:** "Discard changes?" when leaving with unsaved changes; "Delete this entry?" when deleting.
- Optimise for speed: a user in pain should be able to tap a mood, tap one symptom chip and tap Save.

### E. Ask tab: "Ask your journal" (on-device AI)
Design all of these states:
1. **Model not installed.** Explain the feature and the offline promise, and give a button to set up the model. Show 3 example questions as non-interactive chips. Note that the journal works without the model.
2. **Downloading.** Progress bar, with a note that journaling still works in the meantime.
3. **Unsupported device.** Calm explanation that AI is off on this phone.
4. **Ready: chat.**
   - Question input with send, and suggested questions.
   - **Answers stream in word by word**, with a visible **Stop** button while generating.
   - Each answer shows **citations**: small numbered chips or cards linking to the journal entries used ("Tue 15 Sep · Migraine · Mood: Low"). Tapping one opens that entry.
   - A **refusal / not enough data** state: "I couldn't find entries about that."
   - A persistent small disclaimer: "Answers come only from your entries. Not medical advice."
5. **Action approval card.** The AI can propose actions. Example: user says "Remind me to take my tablet at 9pm every day". The AI shows a card, *Create reminder · "Take tablet" · Every day at 21:00*, with **Approve** / **Edit** / **Cancel**. Nothing happens until the user approves. Show the success state after approval.

### F. Summaries
- **Weekly summary:** mood and symptom pattern, and possible links (e.g. sleep vs. migraines), written in plain language with citations.
- **Doctor visit summary:** pick a date range, preview a clean one-page report (mood trend, symptom frequency, medications taken, notable notes), then **Export PDF** / Share. The PDF itself should look professional and print well in black and white.

### G. Settings tab
- **Security:** App lock (On/Off with status text "Locks after 30 s in the background"), Unlock with biometrics (toggle), Lock now.
- **Privacy:** "What stays on this phone" (opens the privacy screen). "Cloud AI fallback" toggle, **off by default**: when on, it requires explicit consent and redacts names, dates and places before sending. Show both the disabled state and the consent dialog.
- **AI model:** opens the Model manager.
- **Your data:** Export my data · **Delete all journal data** (destructive, with a strong confirmation).
- **About:** "Not medical advice" statement, version.

### H. Privacy screen
A readable, reassuring explainer. Use one short section per item, each with an icon:
- Encrypted database (AES-256; the key is kept in the phone's secure keystore).
- No network for your data.
- On-device dictation.
- App lock and app-switcher blur.
- Not included in cloud backups.
- **What this can't protect against** (someone holding your unlocked phone while the app is open).
- You're in control (delete an entry, or erase everything).

### I. App lock
- **Lock screen:** app icon/mark, "Mindfull is locked", PIN dots (4–8 digits), a custom numeric keypad (no system keyboard), a Face ID / fingerprint key, and a backspace key. States:
  - Wrong PIN: "Wrong PIN. 3 tries left."
  - Lockout with countdown: "Too many attempts. Try again in 0:28."
- **Set up flow:** Choose a PIN → Confirm your PIN (mismatch error) → done. When a lock already exists: Change PIN / Turn off (both ask for the current PIN first).
- **Privacy shield:** what the app looks like in the app switcher. The content is fully blurred or covered, with only the app mark visible.

### J. Model manager
Installed models, with name, size on disk, and measured speed on this device (tokens/sec). Also show the active model, switch model, delete, re-download, and the download states from onboarding.

### K. Benchmarks (developer screen, can be plain)
A table or cards for tokens/sec, time to first token, peak RAM, and battery use per 10 prompts. Add a "Run benchmark" button and a history of runs. Functional, not decorative.

---

## 5. Visual direction (starting point; improve on it)

- Current seed colour: **calm sage green `#4F7F6E`**. You may propose a better palette, but keep it calm and natural.
- Current mood colour ramp (colour-blind-friendly, orange → teal, never red/green): Very low `#D9764A`, Low `#E0A24E`, Okay `#B5B06A`, Good `#6FA88F`, Great `#3F8C8C`. Mood is always shown with a face icon and label as well.
- Symptoms and medications need distinct but related chip styles (e.g. tonal vs. outlined, with a small pill icon for medication).
- Soft, rounded shapes (12–16 pt radii), generous whitespace, and low-contrast surfaces instead of heavy shadows.
- Typography: one highly legible family with a clear scale. Body text is comfortable to read in bed, at night, in dark mode.
- Iconography: one consistent outlined icon set.
- Motion: subtle and brief. Respect "reduce motion". The streaming AI answer is the only place where continuous motion is expected.
- Copy tone: plain, kind, second person, short. Never alarmist, never diagnostic ("may be linked", not "causes").

---

## 6. What to deliver

1. **Design system:**
   - Colour tokens for light and dark (primary, surfaces, text, outline, error, mood ramp, symptom and medication chips).
   - Type scale, spacing scale, radii and elevation.
   - Components: buttons, chips, cards, entry card, mood picker, tag picker, PIN keypad, network pill, citation chip, action approval card, bottom sheet, dialogs, empty states.
2. **Every screen in section 4**, in light mode, with the key screens (Journal, New entry, Ask chat, Lock screen) also in **dark mode**.
3. **All listed states** for each screen (empty, loading, error, model not ready / downloading / unsupported / ready, streaming, approval, lockout).
4. A **short rationale** (a few bullets per key screen) explaining layout choices, especially how the design keeps logging fast and makes privacy feel reassuring.
5. Use **realistic sample data**, not lorem ipsum. Example: a user with migraines; entries across two weeks; symptoms such as Migraine, Nausea, Light sensitivity, Fatigue; medications such as Sumatriptan 50mg and Ibuprofen 400mg; sleep between 5 and 8.5 h; notes such as "Aura started around 10am after a bad night's sleep."

## 7. Don'ts
- No login, sign-up, profile pictures, social or community features.
- No cloud or sync icons that suggest data is uploaded (the cloud-off icon is fine).
- No medical claims, diagnoses or red "alert" styling for health data.
- No streaks, scores, badges or shaming copy.
- No dense dashboards on the home screen. The entry list and "New entry" come first.
