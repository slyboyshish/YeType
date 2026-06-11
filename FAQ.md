# YeType FAQ

Frequently asked questions about YeType, the free, open-source, on-device AI
autocomplete for macOS.

## 1. What is YeType and how does it work?

YeType is a free, open-source macOS menu bar app that adds AI autocomplete to
almost any text field on your Mac. As you type, it shows a gray "ghost text"
suggestion inline next to your cursor. Press `Tab` to accept it, or just keep
typing to ignore it.

Under the hood, YeType notices which text field you are focused on, reads what
you have typed (and optionally the surrounding on-screen context), generates a
short continuation with a local AI model, and inserts the text you accept right
where your cursor is.

Beyond sentence completion, YeType also includes:

- Inline emoji autocomplete (type `:smile` and accept).
- Slash macros for quick math, unit and currency conversion, dates, and more
  (type `/`).
- Autocorrect that fixes typos with a single keystroke.

YeType is currently in beta.

## 2. Is YeType free?

Yes. YeType is completely free and open source, released under the GNU Affero
General Public License v3.0 (AGPL-3.0). There is no subscription, no account, and
no paid tier. You are free to read, modify, and redistribute the source under the
terms of that license. The code lives at
[github.com/slyboyshish/yetype](https://github.com/slyboyshish/yetype).

The downloadable AI models are free too, and Apple Intelligence is built into
macOS, so there are no usage costs of any kind.

## 3. Is my data private? Does YeType send what I type to the cloud?

Privacy is the core design principle. Everything that produces a suggestion runs
on your Mac:

- All AI text generation happens on-device, using either Apple Intelligence
  (built into macOS) or a local model running directly on your machine. There is
  no hosted API and no cloud round-trip.
- When screen context is used, the screenshot is captured and read entirely
  on-device with Apple's built-in text recognition. No images or recognized text
  are ever uploaded.
- YeType contains no analytics, no telemetry, and no crash reporting.

The only times YeType uses the network are to download an AI model when you
choose to, to let you search for models in the optional in-app model browser, and
to check for app updates. None of these carry the text you type, your
suggestions, or anything from your screen.

For the technically curious: a normal install never writes your typed text to
disk. Only special developer debug builds write local diagnostic logs, and even
those stay on your Mac and are never transmitted.

## 4. What are the system requirements?

- macOS 14 (Sonoma) or later.
- Apple Silicon (M-series) is strongly recommended for good local-model
  performance.
- Free disk space for any local models you download (from under 1 GB to around
  5 GB each, depending on the model you pick).
- To use the Apple Intelligence engine specifically, you need macOS 26 or later
  on a Mac that supports Apple Intelligence, with Apple Intelligence turned on in
  System Settings. On older Macs, use the built-in Open Source engine instead.

## 5. How do I install YeType?

There are three ways:

- **Homebrew (recommended):**
  ```sh
  brew tap slyboyshish/yetype
  brew install --cask yetype
  ```
  Update later with `brew upgrade --cask yetype`.
- **Direct download:** get the latest release from
  [yetype.app](https://yetype.app) (or the GitHub Releases page) and drag
  YeType into your Applications folder.
- **Build from source:** clone
  [github.com/slyboyshish/yetype](https://github.com/slyboyshish/yetype) and open the
  project in Xcode.

After launching, YeType lives in your menu bar and walks you through a short
setup. It checks for and installs updates automatically when new versions ship.

## 6. Why does YeType need Accessibility, Input Monitoring, and Screen Recording permissions?

YeType works inside other apps, so macOS requires you to grant three
permissions. Each one maps to a specific feature:

- **Accessibility:** to read the text and cursor position in the field you are
  typing in, and to insert the text you accept.
- **Input Monitoring:** to notice your typing so it knows when to suggest, and to
  recognize the accept key (`Tab`).
- **Screen Recording:** to capture the area around your cursor for visual
  context, which makes suggestions more relevant.

YeType guides you through granting each one during setup and shows a reminder if
a permission is later turned off. You can change them anytime in System Settings
under Privacy & Security. YeType never operates in password or other secure
fields.

## 7. How do I use YeType, and how do I accept or dismiss a suggestion?

Start typing in any supported text field. When a suggestion appears as ghost
text:

- Press `Tab` to accept it. By default `Tab` accepts one word (or a full phrase,
  depending on your Acceptance Mode setting).
- Press the accept-entire-suggestion key (backtick `` ` `` by default) to take
  the whole suggestion at once.
- Keep typing to ignore the suggestion, or press `Esc` to dismiss it.

All of these keys are rebindable in Settings, under Shortcuts, so you can pick
whatever feels natural.

## 8. Which apps does YeType work in?

YeType works system-wide in almost any standard, editable text field, including
native Mac apps and most web and Electron apps (such as Chrome).

For your safety and privacy, it deliberately stays out of:

- Password and other secure or sensitive fields (passcodes, card numbers,
  one-time codes, and the like).
- Terminal apps (Terminal, iTerm2, and others).

Some browser and Electron editors expose their contents to macOS a little
differently, so YeType includes special handling for them. If a particular
field does not expose what YeType needs, it simply stays quiet there.

## 9. Which AI model does YeType use, and does it work offline?

YeType gives you two engines, and you choose which one to use:

- **Apple Intelligence:** Apple's on-device model built into macOS (requires
  macOS 26 or later on a supported Mac). Nothing to download.
- **Open Source:** a local model that runs directly on your Mac. You can pick
  from several tiers, from a lightweight model (under 1 GB) up to a larger,
  higher-quality one (around 5 GB). Larger models write better but run slower.
  You can also import your own GGUF model or browse Hugging Face from inside the
  app.

Both engines run entirely on your Mac. Once a model is downloaded (or Apple
Intelligence is set up), suggestions work fully offline, with no internet
required.

## 10. How do I customize YeType or turn it off?

Open Settings from the menu bar icon. A few of the things you can adjust:

- Suggestion length, multi-line suggestions, and Fast Mode (which skips screen
  context for faster results).
- Ghost text color and opacity, and whether suggestions appear inline or as a
  popup.
- Engine and model selection, emoji style, slash macros, and your keyboard
  shortcuts.

To pause YeType:

- Turn off "Enable Globally" in the menu or General settings to disable it
  everywhere without quitting.
- Add specific apps to the Disabled Apps list (or toggle it off for the app you
  are currently in) to silence it just there.
- Set a global toggle shortcut in Settings, under Shortcuts, to flip it on and
  off from the keyboard.

To quit entirely, choose Quit from the menu bar.
