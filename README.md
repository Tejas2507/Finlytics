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
  <img src="https://img.shields.io/badge/AI-Gemini%202.5-4285F4?style=for-the-badge&logo=google" alt="Gemini"/>
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
- **Monthly income vs expense flow** visualization
- **Category breakdown** with interactive donut charts
- **AI-powered daily insights** that are witty and actionable

### 🤖 AI Financial Assistant
- **Natural language chat** — Ask anything about your finances
- **Context-aware responses** using your transaction history
- **Budget tracking integration** — AI knows your spending limits
- **Markdown & table support** for rich, formatted responses
- Powered by **Google Gemini 2.5 Flash/Pro**

### 💰 Smart Budget Management
- **AI-generated budget suggestions** based on spending patterns
- **Visual progress bars** with color-coded status (green/orange/red)
- **Category-wise tracking** with icons and colors
- **Collaborative review** — Accept, modify, or reject AI proposals

### 📝 Transaction Management
- **Manual entry** with categorization
- **Smart Paste** — Copy SMS/text and let AI parse the transaction
- **Edit & delete** with swipe actions
- **Search & filter** by category, type, or date
- **Vault** — Hide sensitive transactions behind Face ID/passcode

### 🔐 Privacy First
- **100% local storage** using SwiftData
- **Keychain-secured** API key storage
- **No cloud sync** — Your data never leaves your device
- **Deep Dark Mode** — Premium, battery-saving dark interface natively enforced

---

## 📱 Screenshots

<p align="center">
  <em>Coming soon! The app features a premium dark-mode interface with vibrant gradients, smooth animations, and glassmorphic elements.</em>
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
   git clone https://github.com/yourusername/Finlytics.git
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
   - Enter your Gemini API key
   - Get one free at [aistudio.google.com](https://aistudio.google.com)

---

## 🚀 Usage

### Adding Transactions

#### Manual Entry
1. Tap the **+** button on the Transactions tab
2. Select Income or Expense
3. Enter amount, merchant, category
4. Save!

#### Smart Paste (AI-Powered)
1. Copy a bank SMS or transaction text
2. Open Add Transaction
3. Tap **"Read from Clipboard (Smart Paste)"**
4. AI will parse and auto-fill the fields

### Getting AI Insights
- Navigate to the **AI Chat** tab
- Ask questions like:
  - *"How much did I spend on food this month?"*
  - *"Am I overspending compared to last month?"*
  - *"Give me a breakdown of my expenses"*

### Setting Budgets
- Go to **Smart Budget** tab
- Tap **"Generate AI Budgets"** for smart suggestions
- Or tap **+** to add manual budgets
- Track progress with visual indicators

---

## 📂 Project Structure

```
Finlytics/
├── FinSenseApp.swift          # App entry point
├── Models/
│   ├── Transaction.swift      # Transaction model with Smart Parse
│   ├── Budget.swift           # Budget model
│   ├── Category.swift         # Category definitions & colors
│   └── Insight.swift          # Daily insight model
├── Views/
│   ├── RootView.swift         # Tab navigation
│   ├── SplashView.swift       # Launch animation
│   ├── DashboardView.swift    # Main dashboard with charts
│   ├── DashboardHeader.swift  # Balance & insight cards
│   ├── TransactionsView.swift # Transaction list
│   ├── AddTransactionView.swift # Add/edit transactions
│   ├── HiddenTransactionsView.swift # Secure vault for hidden transactions
│   ├── AIInsightsView.swift   # Chat interface
│   ├── SmartBudgetView.swift  # Budget management
│   ├── BudgetSuggestionView.swift # AI proposal review
│   ├── SettingsView.swift     # App settings
│   └── ContentView.swift      # Main navigation and app container
├── Services/
│   ├── AIManager.swift        # AI API integration & response generation
│   ├── InsightEngine.swift    # Daily insight generation
│   ├── AIPersonaEngine.swift  # Internal agent persona profiling
│   ├── KeychainHelper.swift   # Secure key storage
│   └── DataSeeder.swift       # Demo data generator
└── Assets.xcassets/           # App icons & images
```

---

## 🎨 Design Philosophy

Finlytics follows these principles:

1. **Local-First** — Your financial data is sensitive. It stays on your device.
2. **AI-Augmented** — AI enhances, not replaces, your financial decisions.
3. **Delightful UX** — Smooth animations, intuitive gestures, beautiful charts.
4. **Indian Context** — Built with ₹ INR as the primary currency, SMS parsing for Indian banks.

---

## 🔑 API Key Setup

1. Visit [Google AI Studio](https://aistudio.google.com)
2. Sign in with your Google account
3. Click **"Get API Key"**
4. Copy the key
5. In Finlytics, go to **Settings > AI Configuration**
6. Paste and save

> **Note:** Your API key is stored securely in the iOS/macOS Keychain and never transmitted anywhere except to Google's API.

---

## 🗺 Roadmap

- [ ] Widget support for quick balance view
- [ ] Recurring transactions
- [ ] Bill reminders
- [ ] Multi-currency support
- [ ] iCloud sync (opt-in)
- [ ] Siri shortcuts integration
- [ ] Apple Watch companion app

---

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

---

## 📄 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- [Google Generative AI](https://ai.google.dev/) for the powerful Gemini API
- [Swift Charts](https://developer.apple.com/documentation/charts) for beautiful visualizations
- The SwiftUI community for inspiration

---

<p align="center">
  Made with ❤️ for better financial awareness
</p>

<p align="center">
  <strong>Star ⭐ this repo if you find it useful!</strong>
</p>
