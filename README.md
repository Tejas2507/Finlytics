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
  <img src="https://img.shields.io/badge/AI-Gemini%202.0%20Flash-4285F4?style=for-the-badge&logo=google" alt="Gemini"/>
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
- **Project Detail Analytics** — Deep-dive searches, category breakdowns, and spending trends specific to each project

### 🤖 AI Strategy Engine
- **Financial Strategist (Main)** — Ask anything about your performance and spending trends via the main AI Chat
- **App Expert (Help Mode)** — A dedicated AI in Settings that knows the app manual inside out, providing step-by-step guidance without seeing your financial data
- **Isolated Context Architecture** — Strategic isolation between your private data and app help to ensure maximum privacy
- **Markdown & table support** for rich, formatted responses

### 💰 Smart Budget Management
- **AI-generated budget suggestions** based on spending patterns
- **Visual progress bars** with color-coded status (green/orange/red)
- **Collaborative review** — Accept, modify, or reject AI proposals

### 📝 Transaction Intelligence
- **Smart Paste (AI-Powered)** — Copy SMS/text and let AI parse the transaction automatically
- **Merchant Auto-naming** — AI intelligently cleans up merchant names and suggests relevant categories
- **Precise Timestamps** — Record and edit transactions with granular hour/minute detail
- **Search & filter** by category, merchant, or date across all tabs

### 🔐 Privacy First
- **100% local storage** using SwiftData
- **Keychain-secured** API key storage
- **Hidden Vault** for private transactions protected by biometrics/passcode
- **No cloud sync** — Your data never leaves your device

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
| **AI Integration** | Google Generative AI SDK |
| **Secure Storage** | Keychain Services |
| **Architecture** | MVVM-ish (View-centric) |

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

3. **Add the Google Generative AI Package**
   - In Xcode, go to `File > Add Package Dependencies`
   - Enter: `https://github.com/google/generative-ai-swift`
   - Add to your target

4. **Build & Run**
   - Select your target device (iPhone/Mac)
   - Press `Cmd + R`

5. **Configure API Key**
   - Go to Settings in the app
   - Enter your Gemini API key from [aistudio.google.com](https://aistudio.google.com)

---

## 🚀 Usage

### Organizing with Projects
1. Go to the **Projects** tab.
2. Tap **+** to create a project (e.g., "Paris Trip").
3. Link transactions directly from the "Add Transaction" screen or by swiping on existing transactions.
4. **Hide** sensitive projects by swiping left and selecting "Hide" to move them into the Vault.

### Dual-AI Interaction
- **Tab 5 (AI Chat)**: Talk to the Financial Strategist about your wealth.
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
│   └── Insight.swift          # Daily insight model
├── Views/
│   ├── DashboardView.swift    # Main dashboard with auto-scrolling tutorial
│   ├── ProjectsListView.swift # (New) Grouped projects and Vault access
│   ├── ProjectDetailView.swift # (New) Detailed project analytics
│   ├── TransactionsView.swift # Transaction list with full search
│   ├── AddTransactionView.swift # Transaction editor with Time support
│   ├── AIInsightsView.swift   # Financial strategist chat
│   ├── SmartBudgetView.swift  # Budget management
│   ├── SettingsView.swift     # App settings & Help Expert access
│   ├── HiddenTransactionsView.swift # The Secure Vault
│   └── TutorialOverlay.swift  # Interactive onboarding UI
├── Services/
│   ├── AIManager.swift        # Primary AI logic with Persona & Help modes
│   ├── AIPersonaEngine.swift  # Financial Analyst behavior engine
│   ├── MerchantAnalytics.swift# Intelligent merchant naming logic
│   ├── InsightEngine.swift    # Daily financial insight generation
│   ├── KeychainHelper.swift   # Secure key storage
│   └── TutorialManager.swift  # Multi-step Onboarding logic
└── Assets.xcassets/           # App icons & images
```

---

## 🎨 Design Philosophy

Finlytics follows these principles:

1. **Local-First** — Your financial data is sensitive. It stays on your device.
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
- [x] Transaction Time-editing support
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
