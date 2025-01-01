# typed: strict
# frozen_string_literal: true

module Copilot
  extend T::Sig

  # Returns a Copilot object for a given account object. This is useful in
  # instances where we don't know the type of account. For other instances, we
  # should still use Copilot::User.new/etc.
  sig { params(account: T.any(::User, ::Organization, ::Business)).returns(T.any(Copilot::User, Copilot::Organization, Copilot::Business)) }
  def self.copilot_object(account)
    case account
    when ::Business
      Copilot::Business.new(account)
    when ::Organization
      Copilot::Organization.new(account)
    when ::User
      Copilot::User.new(account)
    else
      T.absurd(account)
    end
  end

  # Returns a free trial length for Copilot
  sig { returns(Integer) }
  def self.free_trial_length
    COPILOT_FREE_TRIAL_LENGTH
  end

  sig { params(mailable: T.nilable(T.any(::User, ::Organization, ::Business))).returns(T::Boolean) }
  def self.copilot_communication_opt_out?(mailable)
    return false unless mailable.present?
    Copilot.copilot_object(mailable).copilot_communication_opt_out?
  end

  # TODO: Update when we provide seat management UI for enterprises
  # Type Aliases for ORGANIZATION LINKED ASSIGNABLES
  OrganizationAssignable = T.type_alias { T.any(::User, ::Team, ::OrganizationInvitation, ::Organization) }
  Assignable = T.type_alias { T.any(::User, ::Team, ::OrganizationInvitation, ::Organization, ::EnterpriseTeam) }
  Owner = T.type_alias { T.any(::Organization, ::Business) }

  Objectable = T.type_alias do
    T.nilable(T.any(
      ::Business,
      ::Organization,
      ::User,
      Copilot::Business,
      Copilot::FreeUser,
      Copilot::Organization,
      Copilot::User,
    ))
  end

  COPILOT_ENGAGED_OSS_LANGUAGES = T.let([
    "C",
    "C#",
    "C++",
    "Clojure",
    "CoffeeScript",
    "Dart",
    "DM",
    "Elixir",
    "Erlang",
    "F#",
    "Fortran",
    "Go",
    "Groovy",
    "Haskell",
    "HTML",
    "Java",
    "JavaScript",
    "Julia",
    "Jupyter Notebook",
    "Kotlin",
    "Lua",
    "Makefile",
    "MATLAB",
    "Objective-C",
    "OCaml",
    "Perl",
    "PHP",
    "PowerShell",
    "Python",
    "R",
    "Ruby",
    "Rust",
    "Scala",
    "Shell",
    "Swift",
    "TeX",
    "TSQL",
    "TypeScript",
    "Vim script"
  ].freeze, T::Array[String])

  if Rails.env.development? || Rails.env.test?
    COPILOT_FOR_BUSINESS_SEAT_DELAYS = T.let({
      ENTERPRISE_TEAM: 0.seconds,
      ORGANIZATION: 0.seconds,
      TEAM: 0.seconds,
      USER: 0.seconds,
    }.freeze, T::Hash[Symbol, ActiveSupport::Duration])
  else
    COPILOT_FOR_BUSINESS_SEAT_DELAYS = T.let({
      ENTERPRISE_TEAM: 15.minutes,
      ORGANIZATION: 30.minutes,
      TEAM: 15.minutes,
      USER: 1.minute,
    }.freeze, T::Hash[Symbol, ActiveSupport::Duration])
  end

  GITHUB_ORG_ID = T.let(9919, Integer)
  MICROSOFTCOPILOT_ORG_ID = T.let(107488659, Integer)
  MS_COPILOT_ORG_ID = T.let(113467149, Integer)
  OPENAI_ORG_ID = T.let(14957082, Integer)

  COPILOT_TELEMETRY_ORG_IDS = T.let([
    GITHUB_ORG_ID,
    MICROSOFTCOPILOT_ORG_ID,
    OPENAI_ORG_ID,
  ], T::Array[Integer])

  COPILOT_FREE_TRIAL_LENGTH = T.let(30, Integer)
  COPILOT_ENTERPRISE_TEAM_MAX_SEATS_DEFAULT = T.let(1000, Integer)

  # General Copilot Documentation
  COPILOT_DOCUMENTATION = T.let("https://docs.github.com/copilot".freeze, String)
  COPILOT_LEARN_MORE_PAGE = T.let("https://copilot.github.com/".freeze, String)
  COPILOT_QUICKSTART = T.let("https://docs.github.com/en/copilot/quickstart".freeze, String)
  COPILOT_FEEDBACK_FORUM = T.let("https://github.com/orgs/community/discussions/categories/copilot".freeze, String)
  COPILOT_GETTING_STARTED = T.let("https://github.com/features/copilot/getting-started".freeze, String)
  COPILOT_GETTING_STARTED_VIDEO = T.let("https://www.youtube.com/watch?v=Fi3AJZZregI".freeze, String)
  BETA_TERMS_OF_SERVICE = T.let("https://docs.github.com/en/site-policy/github-terms/github-terms-of-service#j-beta-previews".freeze, String)
  LEARNING_PATHWAY = T.let("https://github.blog/developer-skills/github/github-copilot-learning-pathway-accelerate-your-business-with-ai/".freeze, String)
  PRE_RELEASE_TERMS = T.let("https://docs.github.com/en/site-policy/github-terms/github-pre-release-license-terms".freeze, String)

  # Billing and Pricing
  CONTACT_SALES_TEAM = T.let("https://github.com/enterprise/contact".freeze, String)
  COPILOT_PRICING_PAGE = T.let("https://github.com/features/copilot/#pricing".freeze, String)
  COPILOT_BILLING_DOCUMENTATION = T.let("https://docs.github.com/billing/managing-billing-for-github-copilot/about-billing-for-github-copilot".freeze, String)

  # Terms and Policies
  COPILOT_SPECIFIC_TERMS = T.let("https://github.com/customer-terms/github-copilot-product-specific-terms".freeze, String)
  COPILOT_TRADE_CONTROLS_DOCUMENTATION = T.let("https://docs.github.com/site-policy/other-site-policies/github-and-trade-controls".freeze, String)
  COPILOT_TRUST_CENTER_PRIVACY = T.let("https://resources.github.com/copilot-trust-center/#privacy".freeze, String)
  COPILOT_DATA_RESIDENCY_DOCUMENTATION = T.let("https://docs.github.com/en/enterprise-cloud@latest/early-access/admin/preview-of-data-residency-for-github-enterprise/about-data-residency-in-the-european-union#data-stored-outside-of-the-eu".freeze, String)

  # Copilot Individuals
  COPILOT_FOR_INDIVIDUALS_BILLING_DOCUMENTATION = T.let("https://docs.github.com/billing/managing-billing-for-github-copilot/managing-your-github-copilot-subscription-for-your-personal-account".freeze, String)
  COPILOT_FOR_INDIVIDUALS_DOCUMENTATION = T.let("https://docs.github.com/copilot/overview-of-github-copilot/about-github-copilot-for-individuals".freeze, String)

  # Copilot Business
  COPILOT_FOR_BUSINESS_DOCUMENTATION = T.let("https://docs.github.com/copilot/overview-of-github-copilot/about-github-copilot-for-business".freeze, String)

  # Copilot Enterprise
  COPILOT_FOR_ENTERPRISE_DOCUMENTATION = T.let("https://github.co/copilot-enterprise".freeze, String)

  # Public Code Suggestions
  COPILOT_PUBLIC_CODE_SUGGESTIONS_DOCS = T.let("https://docs.github.com/en/copilot/configuring-github-copilot/configuring-github-copilot-settings-on-githubcom#enabling-or-disabling-duplication-detection".freeze, String)

  # Copilot Chat in the IDE
  COPILOT_CHAT_IDE_DOCS = T.let("https://docs.github.com/en/copilot/github-copilot-chat/about-github-copilot-chat".freeze, String)
  COPILOT_CHAT_EDITOR_DOCS = T.let("https://docs.github.com/copilot/github-copilot-chat/using-github-copilot-chat-in-your-ide".freeze, String)
  COPILOT_CHAT_TUTORIAL_VIDEO = T.let("https://www.youtube.com/watch?v=ZDbk5M4hbEI".freeze, String)
  COPILOT_CHAT_FAQ = T.let("https://github.co/copilot-chat-faqs".freeze, String)
  COPILOT_CHAT_TERMS = T.let("https://github.co/copilot-chat-terms".freeze, String)
  COPILOT_CHAT_TRANSPARENCY_INFO = T.let("https://github.co/copilot-chat-transparency".freeze, String)

  COPILOT_CHAT_JETBRAINS_FEEDBACK_FORUM = T.let("https://gh.io/copilot-chat-jb-feedback".freeze, String)
  COPILOT_CHAT_JETBRAINS_DOCS = T.let("https://gh.io/copilot-chat-get-started-jetbrains".freeze, String)
  COPILOT_CHAT_JETBRAINS_VIDEO_INSTRUCTIONS = T.let("https://gh.io/copilot-chat-jetbrains-video-instructions".freeze, String)

  COPILOT_CHAT_VS_DOCS = T.let("https://github.co/copilot-chat-get-started-vs".freeze, String)
  COPILOT_CHAT_VS_CODE_DOCS = T.let("https://github.co/copilot-chat-get-started-vscode".freeze, String)

  COPILOT_CHAT_VS_ISSUES = T.let("https://learn.microsoft.com/visualstudio/ide/how-to-report-a-problem-with-visual-studio?view=vs-2022".freeze, String)
  COPILOT_CHAT_VS_CODE_ISSUES = T.let("https://github.com/microsoft/vscode-copilot-release/issues".freeze, String)

  # Copilot in github.com
  COPILOT_DOTCOM_CHAT_DOCUMENTATION = T.let("https://docs.github.com/enterprise-cloud@latest/copilot/github-copilot-enterprise/copilot-chat-in-github/using-github-copilot-chat-in-githubcom".freeze, String)

  # Copilot in the CLI
  COPILOT_FOR_CLI_DOCUMENTATION = T.let("https://docs.github.com/copilot/github-copilot-in-the-cli".freeze, String)
  COPILOT_FOR_CLI_USAGE_DOCUMENTATION = T.let("https://docs.github.com/copilot/github-copilot-in-the-cli/using-github-copilot-in-the-cli".freeze, String)

  # Custom Models
  COPILOT_CUSTOM_MODELS_DOCS = T.let("https://docs.github.com/copilot/overview-of-github-copilot/about-github-copilot-custom-models".freeze, String)

  # PR Summarizations
  COPILOT_FOR_PRS_DOCUMENTATION = T.let("https://docs.github.com/enterprise-cloud@latest/copilot/github-copilot-enterprise/copilot-pull-request-summaries/creating-a-pull-request-summary-with-github-copilot".freeze, String)
  COPILOT_FOR_PRS_TUTORIAL_VIDEO = T.let("https://www.youtube.com/watch?v=LlKjlaHGMr4".freeze, String)

  # Private Docs
  COPILOT_DOCSET_MANAGEMENT = T.let("https://docs.github.com/enterprise-cloud@latest/copilot/github-copilot-enterprise/copilot-docset-management/about-copilot-docset-management".freeze, String)

  # Extensions
  EXTENSIONS_AGREEMENT = T.let("https://gh.io/copilot-extension-agreement".freeze, String)
  EXTENSIONS_DOCS = T.let("https://docs.github.com/en/copilot/using-github-copilot/using-extensions-to-integrate-external-tools-with-copilot-chat".freeze, String)
  EXTENSIONS_LEARN_MORE = T.let("https://github.blog/2024-05-21-introducing-github-copilot-extensions".freeze, String)
  EXTENSIONS_POLICY_DOCS = T.let("https://docs.github.com/en/copilot/managing-copilot/managing-github-copilot-in-your-organization/setting-policies-for-copilot-in-your-organization/managing-policies-for-copilot-in-your-organization#setting-a-policy-for-github-copilot-extensions-in-your-organization".freeze, String)

  # Copilot Chat in GitHub Mobile
  COPILOT_CHAT_MOBILE_DOCS = T.let("https://github.co/copilot-chat-mobile-docs".freeze, String)
  MOBILE_CHAT_TRANSPARENCY_INFO = T.let("https://gh.io/about-github-copilot-chat-in-github-mobile".freeze, String)
  GITHUB_MOBILE_TEST_FLIGHT_DOCS = T.let("https://testflight.apple.com/join/NLskzwi5".freeze, String)
  GITHUB_MOBILE_GOOGLE_PLAY_TESTER_DOCS = T.let("https://play.google.com/apps/testing/com.github.android".freeze, String)
  GITHUB_MOBILE_FEEDBACK_FORUM = T.let("https://github.com/orgs/community/discussions/categories/mobile".freeze, String)
  GITHUB_MOBILE_LANDING_PAGE = T.let("https://github.com/mobile".freeze, String)

  # COPILOT WORKSPACE
  COPILOT_WORKSPACE_DOCS = T.let("https://gh.io/cw-docs".freeze, String)
  GITHUB_NEXT_DISCORD = T.let("https://gh.io/next-discord".freeze, String)

  # Copilot Usage Metrics API
  COPILOT_USAGE_METRICS_API_DOCS = T.let("https://docs.github.com/en/rest/copilot/copilot-usage?apiVersion=2022-11-28", String)
  COPILOT_METRICS_API_NAME = T.let("Copilot Metrics API", String)

  CODESPACES_DEMO_FIRST_VALUE = T.let("FIRST".freeze, String)
  CODESPACES_DEMO_SECOND_VALUE = T.let("SECOND".freeze, String)
  CODESPACES_DEMO_THIRD_VALUE = T.let("THIRD".freeze, String)
  CODESPACES_DEMO_FOURTH_VALUE = T.let("FOURTH".freeze, String)
  CODESPACES_DEMO_FINAL_VALUE = T.let("FINAL".freeze, String)

  COPILOT_SEAT_EMISSION_ERRORS = T.let({
    no_copilot_business: "no_copilot_for_business",
    copilot_business_free: "copilot_for_business_free",
    free_trial: "on_free_trial",
    is_spammy: "is_spammy",
    too_soon: "too_soon",
    is_not_billable: "is_not_billable",
    is_suspended: "is_suspended",
  }.freeze, T::Hash[Symbol, String])

  PRODUCT_KEY           = T.let("v0".freeze, String)
  PRODUCT_TYPE          = T.let("github.copilot".freeze, String)
  DEFAULT_SLACK_CHANNEL = T.let("#copilot-dotcom-ops".freeze, String)
  COPILOT_BLOCK_CHANNEL = T.let("#copilot-block-notifications".freeze, String)

  # Prouct Names
  INDIVIDUAL_PRODUCT_NAME = T.let("Copilot Individual".freeze, String)
  BUSINESS_PRODUCT_NAME = T.let("Copilot Business".freeze, String)
  CLI_UI_NAME = T.let("Copilot in the CLI".freeze, String)
  ENTERPRISE_PRODUCT_NAME = T.let("Copilot Enterprise".freeze, String)
  COPILOT_IN_DOTCOM = T.let("Copilot in github.com".freeze, String)
  COPILOT_CHAT_IN_MOBILE = T.let("Copilot Chat in GitHub Mobile".freeze, String)
  COPILOT_CHAT_IN_IDE = T.let("Copilot Chat in the IDE".freeze, String)
  COPILOT_BING_ACCESS = T.let("Copilot access to Bing".freeze, String)

  # Product Pricing
  COPILOT_BUSINESS_MONTHLY_BASE_PRICE = T.let(19, Integer)
  COPILOT_ENTERPRISE_MONTHLY_BASE_PRICE = T.let(39, Integer)

  sig { returns(String) }
  def self.individual_product_name
    INDIVIDUAL_PRODUCT_NAME
  end

  sig { returns(String) }
  def self.business_product_name
    BUSINESS_PRODUCT_NAME
  end

  sig { returns(String) }
  def self.warn_email
    <<~TEMPLATE
    Hello @{{login}},

    On behalf of the GitHub Security team, I want to first extend our gratitude for your continued use of GitHub and for being a valued member of the GitHub community.

    Recent activity on your account caught the attention of our abuse-detection systems. This activity included use of Copilot that was indicative of scripted interactions or of an otherwise deliberately unusual or strenuous nature. While we have not yet restricted Copilot access for your account, further anomalous activity could result in a temporary suspension of your Copilot access.

    While I’m unable to share specifics on rate limits, per our [Acceptable Use Policies](https://docs.github.com/site-policy/acceptable-use-policies/github-acceptable-use-policies#4-spam-and-inauthentic-activity-on-github), we prohibit all use of our servers for any form of excessive automated bulk activity, as well as any activity that places undue burden on our servers through automated means.

    Please also refer to our Terms for Additional Products and Features for [GitHub Copilot](https://docs.github.com/site-policy/github-terms/github-terms-for-additional-products-and-features#github-copilot).

    Sincerely,
    GitHub Security
    TEMPLATE
  end

  sig { returns(String) }
  def self.block_email
    <<~TEMPLATE
    Hello @{{login}},

    On behalf of the GitHub Security team, I want to first extend our gratitude for your continued use of GitHub and for being a valued member of the GitHub community.

    Recent activity on your account caught the attention of our abuse-detection systems. This activity included use of Copilot that was indicative of scripted interactions or of an otherwise deliberately unusual or strenuous nature. Due to this, we have placed a suspension on your copilot access.

    While I’m unable to share specifics on rate limits, we prohibit all use of our servers for any form of excessive automated bulk activity, as well as any activity that places undue burden on our servers through automated means. Please refer to our Acceptable Use Policies on this topic: https://docs.github.com/site-policy/acceptable-use-policies/github-acceptable-use-policies#4-spam-and-inauthentic-activity-on-github.

    Please also refer to our Terms for Additional Products and Features for GitHub Copilot for specific terms: https://docs.github.com/site-policy/github-terms/github-terms-for-additional-products-and-features#github-copilot.

    Sincerely,
    GitHub Security
    TEMPLATE
  end

  sig { returns(String) }
  def self.warn_remediation_email
    <<~TEMPLATE
    Hello @{{login}},

    According to our records, you may have recently received an email from us indicating that your use of GitHub Copilot was in breach of GitHub’s Product Terms and that further activity could result in a temporary suspension of your Copilot access.

    Any warning email was sent in error and can be safely disregarded.

    We apologize for any inconvenience this may have caused you.

    Sincerely,
    GitHub Security
    TEMPLATE
  end

  sig { returns(String) }
  def self.block_remediation_email
    <<~TEMPLATE
    Hello @{{login}},

    According to our records, you may have recently received an email from us indicating that your use of GitHub Copilot was in breach of GitHub’s Product Terms and that we placed a suspension on your Copilot access.

    Any access suspensions were applied in error and have now been removed.

    We apologize for any inconvenience this may have caused you. If you or other team members are still unable to access Copilot, please reach out to GitHub Support directly from the affected account and we'll be more than happy to help.

    Sincerely,
    GitHub Security
    TEMPLATE
  end

  sig { returns(::Redis) }
  def self.redis
    @copilot_redis ||= T.let(::Redis.new(GitHub.read_redis_config("config/redis_copilot.yml", connect_timeout: 0.2)), T.nilable(::Redis))
  end

  sig { returns(String) }
  def self.github_general_privacy_statement_url
    DocsUrlConfig.url_for("site-policy/github-general-privacy-statement")
  end
end
