<p align="center">
  <img src="https://img.icons8.com/3d-fluency/188/chart.png" alt="Finlytics Logo" width="120"/>
</p>

<h1 align="center">Finlytics</h1>

<p align="center">
  <strong>Your AI-Powered Personal Finance Companion</strong>
</p>

<p align="center">
  <em>A beautiful, local-first expense tracker for iOS & macOS with AI insights powered by Google Gemini</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-iOS%2017%2B%20%7C%20macOS%2014%2B-blue?style=for-the-badge&logo=apple" alt="Platform"/>
  <img src="https://img.shields.io/badge/Swift-5.9-orange?style=for-the-badge&logo=swift" alt="Swift"/>
  <img src="https://img.shields.io/badge/SwiftData-Powered-purple?style=for-the-badge" alt="SwiftData"/>
  <img src="https://img.shields.io/badge/AI-Gemini%20Flash--Lite-4285F4?style=for-the-badge&logo=google" alt="Gemini"/>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="License"/>
  <img src="https://img.shields.io/badge/Local--First-Privacy%20Focused-success?style=flat-square" alt="Privacy"/>
</p>

---

## ✨ Features

### 📊 Smart Dashboard
- **Real-time balance tracking** with beautiful, animated summary cards
- **6-month spending trends** with smooth area charts
- **Interactive Onboarding** — A guided tour that auto-scrolls to highlight core dashboard features
- **Category breakdown** with interactive donut charts
- **AI-powered daily insights** that are witty and actionable

### 📁 Projects & Vaults (New!)
- **Event-Based Tracking** — Organize transactions into specific Projects like "Wedding", "Summer Trip", or "Home Renovation"
- **Secure Vault** — Swipe left to "Hide" sensitive projects into a biometric-protected vault
- **Project Archiving** — Move completed projects (like past trips) to an Archived section to keep your active list clean and prevent them from showing up in transaction tagging
- **Project Detail Analytics** — Deep-dive searches, category breakdowns, and spending trends specific to each project

### 🤖 AI Strategy Engine
- **Verified Financial Queries** — Gemini converts questions into a typed query plan while Swift calculates every amount locally
- **Exact Comparisons** — Ask about categories, merchant groups, projects, budgets, or arbitrary periods with source-backed results
- **Persistent Threads** — Conversations, retry/regenerate state, compact summaries, and follow-ups survive app restarts
- **Transparent Evidence** — Every factual answer identifies its period, calculation, and matched transactions
- **App Expert (Help Mode)** — A dedicated AI in Settings that knows the app manual inside out, providing step-by-step guidance without seeing your financial data
- **Isolated Context Architecture** — Strategic isolation between your private data and app help to ensure maximum privacy

### 💰 Smart Budget Management
- **AI-generated budget suggestions** based on spending patterns
- **Visual progress bars** with color-coded status (green/orange/red)
- **Collaborative review** — Accept, modify, or reject AI proposals

### 📝 Transaction Intelligence
- **Smart Paste (AI-Powered)** — Copy SMS/text and let AI parse the transaction automatically
- **Merchant Auto-naming** — AI intelligently cleans up merchant names and suggests relevant categories
- **Precise Timestamps** — Record and edit transactions with granular hour/minute detail
- **Date-Wise Filtering** — Dedicated calendar picker to filter transactions by exact date with a clean "Apply/Clear" workflow
- **Search & filter** by category or merchant with integrated real-time results

### 🔐 Privacy First
- **Local records and chat storage** using SwiftData
- **Keychain-secured** API key storage
- **Hidden Vault** for private transactions protected by biometrics/passcode
- **Minimal AI context** — Raw transaction history and Vault items are never bulk-uploaded; exact calculations run on-device
- **Bring your own key** — Each user consumes their own Gemini free-tier quota, so there is no shared paid service

> AI requests are sent to the selected provider. Gemini free-tier prompts and outputs may be used by Google to improve its products. Finlytics sends the question and query schema, sends only a compact verified result for narrative advice, may classify unknown merchant names once, may summarize older thread messages, sends clipboard text when you invoke Smart Paste, and sends compact aggregates for optional dashboard/budget AI features. Vault items and bulk transaction histories are not sent.

---

## 📱 Screenshots

<p align="center">
  <em>The app features a premium, forced dark-mode interface with vibrant gradients, glassmorphic UI elements, and smooth animations.</em>
</p>

---

## 🛠 Tech Stack

| Component | Technology |
|-----------|------------|
| **UI Framework** | SwiftUI |
| **Data Persistence** | SwiftData |
| **Charts** | Swift Charts |
| **AI Integration** | Gemini REST API (BYOK) |
| **Secure Storage** | Keychain Services |
| **Architecture** | Local query engine + provider-neutral AI orchestration |

---

## 📦 Installation

### Prerequisites
- Xcode 15.0+
- iOS 17.0+ / macOS 14.0+
- A Google Gemini API Key (free tier available)

### Steps

1. **Clone the repository**
   ```bash
   git clone https://github.com/Tejas2507/Finlytics.git
   cd Finlytics
   ```

2. **Open in Xcode**
   ```bash
   open FinSense.xcodeproj
   ```

3. **Build & Run**
   - Select your target device (iPhone/Mac)
   - Press `Cmd + R`

4. **Configure API Key**
   - Go to Settings in the app
   - Enter your Gemini API key from [aistudio.google.com](https://aistudio.google.com)

### Tests

The shared `FinSense` scheme includes the `FinSenseTests` target. In Xcode, press `Cmd + U` to run query-engine, date-range, planner, Gemini transport, context-budget, and SwiftData persistence tests.

---

## 🚀 Usage

### Organizing with Projects
1. Go to the **Projects** tab.
2. Tap **+** to create a project (e.g., "Paris Trip").
3. Link transactions directly from the "Add Transaction" screen or by swiping on existing transactions.
4. **Hide** sensitive projects by swiping left and selecting "Hide" to move them into the Vault.

### Dual-AI Interaction
- **AI Chat tab**: Create persistent threads and ask exact questions about spending, income, categories, merchants, projects, and time-period comparisons.
- **Settings > App Help**: Ask the App Expert how to use specific features or locate the Vault.

### Smart Paste (AI-Powered)
1. Copy a bank SMS or transaction text.
2. Open Add Transaction.
3. Tap **"Read from Clipboard (Smart Paste)"**.
4. AI will parse and auto-fill the fields, including merchant and category suggestions.

---

## 📂 Project Structure

```
Finlytics/
├── FinSenseApp.swift          # App entry point
├── Models/
│   ├── Transaction.swift      # Transaction model with Intelligent Parsing
│   ├── Project.swift          # (New) Project & Vault model
│   ├── Category.swift         # Category definitions & colors
│   ├── Budget.swift           # Budget model
│   ├── Insight.swift          # Daily insight model
│   ├── MerchantProfile.swift  # Canonical aliases and semantic merchant groups
│   ├── ChatThread.swift       # Persistent financial/help conversations
│   └── ChatMessage.swift      # Durable messages, query evidence, and retry state
├── Views/
│   ├── DashboardView.swift    # Main dashboard with auto-scrolling tutorial
│   ├── ProjectsListView.swift # (New) Grouped projects and Vault access
│   ├── ProjectDetailView.swift # (New) Detailed project analytics
│   ├── TransactionsView.swift # Transaction list with full search
│   ├── AddTransactionView.swift # Transaction editor with Time support
│   ├── AIInsightsView.swift   # Persistent thread detail and evidence UI
│   ├── ChatThreadListView.swift # Thread history, rename, and deletion
│   ├── SmartBudgetView.swift  # Budget management
│   ├── SettingsView.swift     # App settings & Help Expert access
│   ├── HiddenTransactionsView.swift # The Secure Vault
│   └── TutorialOverlay.swift  # Interactive onboarding UI
├── Services/
│   ├── AIManager.swift        # Shared AI features such as Smart Paste
│   ├── AI/                    # Gemini REST transport and provider abstraction
│   ├── Chat/                  # Orchestration, summaries, and bounded context
│   ├── FinanceQuery/          # Typed planner, exact query engine, and evidence
│   ├── MerchantAnalytics.swift# Intelligent merchant naming logic
│   ├── InsightEngine.swift    # Daily financial insight generation
│   ├── KeychainHelper.swift   # Secure key storage
│   └── TutorialManager.swift  # Multi-step Onboarding logic
└── Assets.xcassets/           # App icons & images
```

---

## 🎨 Design Philosophy

Finlytics follows these principles:

1. **Local-First** — Records and calculations stay on-device; optional AI receives only the minimum disclosed context needed for the request.
2. **Context Isolation** — Strategic separation of business and support AI to prevent data leaks.
3. **Delightful UX** — Premium dark-mode aesthetics with intentional animations.
4. **Smart Automation** — Reducing transaction friction via Smart Paste and Merchant intelligence.

---

## 🔑 API Key Setup

1. Visit [Google AI Studio](https://aistudio.google.com)
2. Sign in and click **"Get API Key"**
3. In Finlytics, go to **Settings > AI Configuration**
4. Paste and save

---

## 🗺 Roadmap

- [x] Projects & Vaults functionality
- [x] Dual-Mode AI (Strategy vs Help)
- [x] AI-Powered SMS Parsing (Smart Paste)
- [x] Project Archiving (End Projects)
- [x] Date-Wise Filtering UI
- [x] Persistent AI threads with verified local financial queries
- [ ] Widget support for quick balance view
- [ ] Recurring transactions
- [ ] iCloud sync (opt-in)
- [ ] Siri shortcuts integration
- [ ] Apple Watch companion app

---

## 📄 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

---

<p align="center">
  Made with ❤️ for better financial awareness
</p>

<p align="center">
  <strong>Star ⭐ this repo if you find it useful!</strong>
</p>
