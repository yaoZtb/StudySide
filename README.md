# StudySide

A Mac study companion that reads your selected course window when you ask a question. The interface and default AI replies are in English.

## Get started

1. Open **StudySide.app** on your desktop.
2. Open **More (…) → Model Settings** and choose a provider.
3. Open your PDF or slides, then click **Select Course Window**.
4. Ask a question. Press **Return** to send or **Shift + Return** for a new line.

## Model providers

- **ChatGPT:** Choose **Continue with ChatGPT** and complete the official browser sign-in. Eligible requests use your ChatGPT plan. The app does not switch to paid API usage when your allowance runs out.
- **Claude:** Uses your installed, unmodified official Claude Code client with Sonnet. Click **Open Official Sign-In** if needed. StudySide checks subscription sign-in before sending.
- **Gemini:** Uses the official Antigravity CLI and the Gemini allowance available to your signed-in Google account. Complete **Open Official Sign-In** first. Choose an available Gemini model. Extra AI credits are disabled for these requests.
- **API Key:** Enter a base URL, a vision-capable model ID and your API key. API usage is billed separately. Save the key to Keychain if you want it retained.

StudySide does not read or copy the sign-in tokens of Claude Code or Antigravity CLI. Those official clients manage their own sign-in, records and data settings.

## Window arrangement

After selecting a course window, StudySide tries to place the course on the left and its chat window on the right.

Enable **StudySide** in **System Settings → Privacy & Security → Accessibility** when requested, then click **Arrange Again**. Screen sharing alone does not grant permission to move another app's windows.

Exit full-screen or presentation mode before arranging. Minimum window sizes and available screen space may prevent a side-by-side layout. Automatic arrangement can be disabled in the More menu.

## Appearance

Choose **More (…) → Appearance**. Six styles are available: Minimal Graphite, Midnight, Paper Study, Glacier Blue, Soft Lavender and Iridescent Glass. Your selection is saved.

The app icon has bright book pages with a transparent exterior.

## Conversation controls

- **Pin:** Keep StudySide above other windows. Off by default.
- **Pause:** Stop taking new screenshots. Prior screenshots may still be included as context. Start a new conversation to clear them.
- **Preview Capture:** Check the current window without sending it to AI.
- **Copy Answer:** Copy readable text without Markdown formatting markers.
- **Export Study Notes:** Save a plain-text file without screenshots.
- **New Conversation:** Clear the current conversation.

Titles, bold text, lists and code blocks are formatted in answers. Meaningful symbols in code and equations are preserved. Equation typesetting is not yet implemented.

## Data and settings

Your provider settings and theme remain on this Mac. API keys can be saved in macOS Keychain. ChatGPT connection credentials are kept in Keychain. The application bundle identifier and existing settings are preserved across the English-language update.

ChatGPT/API mode does not automatically save conversation content to a local history file. Claude/Gemini mode creates temporary request files, removes them after completion, and may also retain history through the official client's own settings.

Requests include at most the latest 16 messages and three images. The chat view retains up to 40 messages. Screenshots and questions are sent to the selected provider only when you send a question.

Existing course documents, previous messages, window titles and macOS-owned permission dialogs retain their original language.

## Build

The source contains no third-party Swift dependencies. With Apple Command Line Tools installed, run **build.command** to create **StudySide.app** and **StudySide-Mac.zip** next to the source folder. Run **check.command** for the automated checks.

Apple silicon Mac, macOS 14 or later. Automatic target detection from the system picker requires macOS 15.2 or later; earlier versions can use the window list.
