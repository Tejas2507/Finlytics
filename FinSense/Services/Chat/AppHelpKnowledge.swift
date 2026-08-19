import Foundation

enum AppHelpKnowledge {
    static let manual = """
    Finlytics has five tabs:
    1. Dashboard: balance, spending trends, recent transactions, projects, and monthly analytics.
    2. Transactions: add, edit, search, filter, tag with projects, or hide transactions.
    3. AI Chat: ask questions about visible financial data and receive verified calculations.
    4. Budget: create monthly category budgets and review progress.
    5. Settings: monthly income, AI provider/key, Vault, tutorial, and app help.

    Transactions:
    - Add manually from the Transactions tab.
    - Smart Paste extracts amount, merchant, category, and type from copied text.
    - A transaction can have a precise date/time and multiple project tags.
    - Hidden transactions appear in the Vault and are excluded from AI answers.

    Projects:
    - Create a project from Dashboard > Projects.
    - Assign transactions to active projects.
    - Archive completed projects or hide sensitive projects in the Vault.

    Vault:
    - Open Settings > Vault and authenticate with device biometrics or passcode.
    - Hidden projects and transactions can be restored there.

    AI:
    - The Financial AI tab answers questions about the user's data.
    - This Help chat explains app usage and never receives financial records.
    - Gemini uses the user's own API key stored in Keychain.
    """
}
