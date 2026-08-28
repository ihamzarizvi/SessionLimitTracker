import Foundation

/// App identity, shown in Settings → About and used in packaging metadata.
enum AppInfo {
    static let name = "Session Limit Tracker"
    static let version = "1.0.0"
    static let tagline = "Ambient AI usage limits for macOS — Claude, ChatGPT and Gemini, always in view."
    static let repository = URL(string: "https://github.com/ihamzarizvi/SessionLimitTracker")!
}

/// Developer / authorship details.
enum Developer {
    static let name = "Hamza Rizvi"
    static let fullName = "Syed Hamza Rizvi"
    static let role = "Full-Stack Developer · Founder & CEO, Xsofty"
    static let location = "Islamabad / Global"
    static let website = URL(string: "https://hamzarizvi.com")!
    static let email = "hello@hamzarizvi.com"
    static let github = URL(string: "https://github.com/ihamzarizvi")!
    static let linkedin = URL(string: "https://www.linkedin.com/in/hamzarizvi/")!
    static let copyright = "© 2026 Hamza Rizvi"
}
