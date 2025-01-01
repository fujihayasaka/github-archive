# typed: strict
# frozen_string_literal: true

module Copilot
  DEFAULT_QUOTAS = T.let({
    "chat" => 500,
    "completions" => 4000,
  }, T::Hash[String, Integer])

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
    # copilot_override_copilot_communication_opt_out is a feature flag that allows us to override the
    # copilot_communication_opt_out? method and copilot_communication_opt_out feature flag for testing purposes.
    # for example, GitHub individual employees may be opted out of Copilot communications via test orgs/enterprises,
    # but we still want to be able to test emails in prod/review labs.
    return false if mailable.feature_enabled?(:copilot_override_copilot_communication_opt_out)
    Copilot.copilot_object(mailable).copilot_communication_opt_out?
  end

  # TODO: Update when we provide seat management UI for enterprises
  # Type Aliases for ORGANIZATION LINKED ASSIGNABLES
  OrganizationAssignable = T.type_alias { T.any(::User, ::Team, ::OrganizationInvitation, ::Organization) }
  Assignable = T.type_alias { T.any(::User, ::Team, ::OrganizationInvitation, ::Organization, ::EnterpriseTeam, ::BusinessTeam) }
  Owner = T.type_alias { T.any(::Organization, ::Business) }

  Objectable = T.type_alias do
    T.nilable(T.any(
      ::Business,
      ::Organization,
      ::User,
      Copilot::Business,
      Copilot::FreeUser,
      Copilot::LimitedUser,
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
    COPILOT_SEAT_COOLDOWN_PERIODS = T.let({
      ENTERPRISE_TEAM: 0.seconds,
      BUSINESS_TEAM: 0.seconds,
      ORGANIZATION: 0.seconds,
      TEAM: 0.seconds,
      USER: 0.seconds,
    }.freeze, T::Hash[Symbol, ActiveSupport::Duration])
  else
    COPILOT_SEAT_COOLDOWN_PERIODS = T.let({
      ENTERPRISE_TEAM: 15.minutes,
      BUSINESS_TEAM: 15.minutes,
      ORGANIZATION: 30.minutes,
      TEAM: 15.minutes,
      USER: 1.minute,
    }.freeze, T::Hash[Symbol, ActiveSupport::Duration])
  end

  GITHUB_ORG_ID = T.let(9919, Integer)
  MICROSOFTCOPILOT_ORG_ID = T.let(107488659, Integer)
  MS_COPILOT_ORG_ID = T.let(113467149, Integer)
  MICROSOFT_OPEN_SOURCE_ENT_ID = T.let(1578, Integer)
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
  COPILOT_FEATURES_PAGE = T.let("https://github.com/features/copilot/".freeze, String)
  COPILOT_LEARN_MORE_PAGE = T.let("https://copilot.github.com/".freeze, String)
  COPILOT_QUICKSTART = T.let("https://docs.github.com/en/copilot/quickstart".freeze, String)
  COPILOT_FEEDBACK_FORUM = T.let("https://github.com/orgs/community/discussions/categories/copilot".freeze, String)
  COPILOT_GETTING_STARTED = T.let("https://github.com/features/copilot/tutorials".freeze, String)
  COPILOT_GETTING_STARTED_VIDEO = T.let("https://www.youtube.com/watch?v=Fi3AJZZregI".freeze, String)
  BETA_TERMS_OF_SERVICE = T.let("https://docs.github.com/en/site-policy/github-terms/github-terms-of-service#j-beta-previews".freeze, String)
  EXAMPLE_PROMPTS = T.let("https://docs.github.com/en/copilot/example-prompts-for-github-copilot-chat".freeze, String)
  LEARNING_PATHWAY = T.let("https://github.blog/developer-skills/github/github-copilot-learning-pathway-accelerate-your-business-with-ai/".freeze, String)
  PRE_RELEASE_TERMS = T.let("https://docs.github.com/en/site-policy/github-terms/github-pre-release-license-terms".freeze, String)
  PREVIEW_FEATURES_TERMS = T.let("https://docs.github.com/en/site-policy/github-terms/github-terms-for-additional-products-and-features#previews".freeze, String)
  GITHUB_NEXT_TERMS = T.let("https://github.com/githubnext/githubnext/blob/main/TERMS_AND_CONDITIONS.md".freeze, String)
  COPILOT_ENABLING_ORG_FEATURES_DOC = T.let("https://docs.github.com/en/copilot/managing-copilot/managing-github-copilot-in-your-organization/managing-policies-for-copilot-in-your-organization#enabling-copilot-features-in-your-organization".freeze, String)

  # Billing and Pricing
  CONTACT_SALES_TEAM = T.let("https://github.com/enterprise/contact".freeze, String)
  COPILOT_PRICING_PAGE = T.let("https://github.com/features/copilot/#pricing".freeze, String)
  COPILOT_BILLABLE_CUSTOMER = T.let("Usage billed to".freeze, String)
  COPILOT_BILLING_DOCUMENTATION = T.let("https://docs.github.com/billing/managing-billing-for-github-copilot/about-billing-for-github-copilot".freeze, String)
  COPILOT_SUBSCRIPTION_PLANS_DOC = T.let("https://docs.github.com/en/copilot/about-github-copilot/subscription-plans-for-github-copilot".freeze, String)
  COPILOT_OVERAGES = T.let("Additional Copilot premium requests".freeze, String)

  # Terms and Policies
  COPILOT_SPECIFIC_TERMS = T.let("https://github.com/customer-terms/github-copilot-product-specific-terms".freeze, String)
  COPILOT_TRADE_CONTROLS_DOCUMENTATION = T.let("https://docs.github.com/site-policy/other-site-policies/github-and-trade-controls".freeze, String)
  COPILOT_TRUST_CENTER_PRIVACY = T.let("https://github.com/trust-center".freeze, String)
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
  CFB_PUBLIC_CODE_SUGGESTIONS_DOCS = T.let("https://docs.github.com/en/copilot/using-github-copilot/finding-public-code-that-matches-github-copilot-suggestions".freeze, String)

  # Model docs
  COPILOT_A_CHAT_DOCS = T.let("https://docs.github.com/copilot/using-github-copilot/using-claude-sonnet-in-github-copilot".freeze, String)
  COPILOT_AFOS_DOCS = T.let("https://gh.io/copilot-claude".freeze, String)
  COPILOT_AL_DOCS = T.let("https://gh.io/copilot-claude".freeze, String)
  COPILOT_G_CHAT_DOCS = T.let("https://docs.github.com/copilot/using-github-copilot/ai-models/using-gemini-flash-in-github-copilot".freeze, String)
  COPILOT_G_TF_DOCS = T.let("https://docs.github.com/en/copilot/using-github-copilot/ai-models/using-gemini-in-github-copilot".freeze, String)
  COPILOT_GTFF_DOCS = T.let("https://docs.github.com/en/copilot/using-github-copilot/ai-models/using-gemini-flash-in-github-copilot".freeze, String)
  COPILOT_OFO_DOCS = T.let("https://gh.io/openai-gpt-41".freeze, String)
  COPILOT_O_FM_DOCS = T.let("https://docs.github.com/en/copilot/using-github-copilot/ai-models/using-openai-o4-mini-in-github-copilot".freeze, String)
  COPILOT_O_T_DOCS = T.let("https://docs.github.com/en/copilot/using-github-copilot/ai-models/using-openai-o3-in-github-copilot".freeze, String)


  # Copilot Chat in the IDE
  COPILOT_CHAT_IDE_DOCS = T.let("https://docs.github.com/en/copilot/github-copilot-chat/about-github-copilot-chat".freeze, String)
  COPILOT_CHAT_EDITOR_DOCS = T.let("https://docs.github.com/copilot/github-copilot-chat/using-github-copilot-chat-in-your-ide".freeze, String)
  COPILOT_CHAT_TUTORIAL_VIDEO = T.let("https://www.youtube.com/watch?v=ZDbk5M4hbEI".freeze, String)
  COPILOT_CHAT_FAQ = T.let("https://github.co/copilot-chat-faqs".freeze, String)
  COPILOT_CHAT_TERMS = T.let("https://github.co/copilot-chat-terms".freeze, String)
  COPILOT_CHAT_TRANSPARENCY_INFO = T.let("https://github.co/copilot-chat-transparency".freeze, String)
  EDITOR_PREVIEW_FEATURES_DOCS = T.let("https://docs.github.com/en/copilot/managing-copilot/managing-github-copilot-in-your-organization/managing-policies-for-copilot-in-your-organization#about-policies-for-github-copilot".freeze, String)

  COPILOT_CHAT_JETBRAINS_FEEDBACK_FORUM = T.let("https://gh.io/copilot-chat-jb-feedback".freeze, String)
  COPILOT_CHAT_JETBRAINS_DOCS = T.let("https://gh.io/copilot-chat-get-started-jetbrains".freeze, String)
  COPILOT_CHAT_JETBRAINS_VIDEO_INSTRUCTIONS = T.let("https://gh.io/copilot-chat-jetbrains-video-instructions".freeze, String)

  COPILOT_CHAT_VS_DOCS = T.let("https://github.co/copilot-chat-get-started-vs".freeze, String)
  COPILOT_CHAT_VS_CODE_DOCS = T.let("https://github.co/copilot-chat-get-started-vscode".freeze, String)

  COPILOT_CHAT_VS_ISSUES = T.let("https://learn.microsoft.com/visualstudio/ide/how-to-report-a-problem-with-visual-studio?view=vs-2022".freeze, String)
  COPILOT_CHAT_VS_CODE_ISSUES = T.let("https://github.com/microsoft/vscode-copilot-release/issues".freeze, String)

  # Copilot in GitHub.com
  COPILOT_DOTCOM_CHAT_DOCUMENTATION = T.let("https://docs.github.com/enterprise-cloud@latest/copilot/github-copilot-enterprise/copilot-chat-in-github/using-github-copilot-chat-in-githubcom".freeze, String)

  # Copilot in the CLI
  COPILOT_FOR_CLI_DOCUMENTATION = T.let("https://docs.github.com/copilot/github-copilot-in-the-cli".freeze, String)
  COPILOT_FOR_CLI_USAGE_DOCUMENTATION = T.let("https://docs.github.com/copilot/github-copilot-in-the-cli/using-github-copilot-in-the-cli".freeze, String)

  # Copilot in GitHub Desktop
  COPILOT_IN_DESKTOP_DOCUMENTATION = T.let("https://gh.io/using-copilot-in-github-desktop".freeze, String)

  # Custom Models
  COPILOT_CUSTOM_MODELS_DOCS = T.let("https://docs.github.com/copilot/overview-of-github-copilot/about-github-copilot-custom-models".freeze, String)

  # Copilot Summaries
  COPILOT_FOR_PRS_DOCUMENTATION = T.let("https://docs.github.com/enterprise-cloud@latest/copilot/github-copilot-enterprise/copilot-pull-request-summaries/creating-a-pull-request-summary-with-github-copilot".freeze, String)
  COPILOT_FOR_PRS_TUTORIAL_VIDEO = T.let("https://www.youtube.com/watch?v=LlKjlaHGMr4".freeze, String)

  # Private Docs
  COPILOT_DOCSET_MANAGEMENT = T.let("https://docs.github.com/enterprise-cloud@latest/copilot/github-copilot-enterprise/copilot-docset-management/about-copilot-docset-management".freeze, String)

  # Extensions
  EXTENSIONS_AGREEMENT = T.let("https://gh.io/copilot-extension-agreement".freeze, String)
  EXTENSIONS_DOCS = T.let("https://docs.github.com/en/copilot/using-github-copilot/using-extensions-to-integrate-external-tools-with-copilot-chat".freeze, String)
  EXTENSIONS_LEARN_MORE = T.let("https://github.blog/2024-05-21-introducing-github-copilot-extensions".freeze, String)
  EXTENSIONS_POLICY_DOCS = T.let("https://docs.github.com/en/copilot/managing-copilot/managing-github-copilot-in-your-organization/setting-policies-for-copilot-in-your-organization/managing-policies-for-copilot-in-your-organization#setting-a-policy-for-github-copilot-extensions-in-your-organization".freeze, String)

  # Tooling
  COPILOT_MCP_SERVERS = T.let("MCP servers on GitHub.com".freeze, String)

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
  COPILOT_WORKSPACE_FEEDBACK = T.let("https://gh.io/workspace-feedback".freeze, String)
  COPILOT_WORKSPACE_DISCUSSION = T.let("https://gh.io/copilot-pull-request-workspace".freeze, String)

  # Copilot Usage Metrics API
  COPILOT_USAGE_METRICS_API_DOCS = T.let("https://docs.github.com/en/rest/copilot/copilot-metrics?apiVersion=2022-11-28", String)
  COPILOT_METRICS_API_NAME = T.let("Copilot Metrics API", String)

  # Copilot Models
  MODELS_DOCS = T.let("https://docs.github.com/en/github-models/prototyping-with-ai-models".freeze, String)
  MODEL_PICKER_PREVIEW_URL = T.let("https://gh.io/model-picker-blog", String)
  MODEL_PICKER_DISCUSSION_URL = T.let("https://gh.io/model-picker-discussion", String)

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
    is_deleted: "is_deleted",
    is_archived: "is_archived"
  }.freeze, T::Hash[Symbol, String])

  # Billing Product Identifiers
  #
  # Note: Mobile also uses these identifiers to identify the product types for in-app purchasing, but since
  # the code which uses them is in the Billing package and cannot use these constants, we are
  # duplicating them there:
  # packages/billing/app/public/billing/public/in_app_purchasing/copilot_subscription_item.rb
  PRODUCT_TYPE = T.let("github.copilot".freeze, String)
  INDIVIDUAL_PRO_PRODUCT_KEY = T.let("v0".freeze, String)
  INDIVIDUAL_PRO_PLUS_PRODUCT_KEY = T.let("pro-plus".freeze, String)
  INDIVIDUAL_PRODUCT_KEYS = T.let([INDIVIDUAL_PRO_PRODUCT_KEY, INDIVIDUAL_PRO_PLUS_PRODUCT_KEY].freeze, T::Array[String])

  # Slack Channels
  DEFAULT_SLACK_CHANNEL = T.let("#copilot-dotcom-ops".freeze, String)
  COPILOT_BLOCK_CHANNEL = T.let("#copilot-block-notifications".freeze, String)

  # Product Names
  INDIVIDUAL_PRODUCT_NAME = T.let("Copilot Individual".freeze, String)
  INDIVIDUAL_PRO_PRODUCT_NAME = T.let("Copilot Pro".freeze, String)
  INDIVIDUAL_PRO_PLUS_PRODUCT_NAME = T.let("Copilot Pro+".freeze, String)
  INDIVIDUAL_FREE_PRODUCT_NAME = T.let("Copilot Free".freeze, String)
  BUSINESS_PRODUCT_NAME = T.let("Copilot Business".freeze, String)
  CLI_UI_NAME = T.let("Copilot in the CLI".freeze, String)
  ENTERPRISE_PRODUCT_NAME = T.let("Copilot Enterprise".freeze, String)
  COPILOT_DEFAULT_CUSTOM_INSTRUCTIONS = T.let("Default organization instructions".freeze, String)
  COPILOT_IN_DOTCOM = T.let("Copilot in GitHub.com".freeze, String)
  COPILOT_CHAT_IN_MOBILE = T.let("Copilot Chat in GitHub Mobile".freeze, String)
  COPILOT_EXTENSION = T.let("Copilot Extensions".freeze, String)
  COPILOT_CHAT_IN_IDE = T.let("Copilot Chat in the IDE".freeze, String)
  COPILOT_BING_ACCESS = T.let("Copilot can search the web".freeze, String)
  COPILOT_A_CHAT = T.let("Anthropic Claude 3.5 Sonnet".freeze, String)
  COPILOT_A_F = T.let("Anthropic Claude 3.7 Sonnet".freeze, String)
  COPILOT_AFOS = T.let("Anthropic Claude Sonnet 4".freeze, String)
  COPILOT_AL = T.let("Anthropic Claude Opus 4".freeze, String)
  COPILOT_G_CHAT = T.let("Google Gemini 2.0 Flash".freeze, String)
  COPILOT_G_TF = T.let("Google Gemini 2.5 Pro".freeze, String)
  COPILOT_GTFF = T.let("Google Gemini 2.5 Flash".freeze, String)
  COPILOT_O1 = T.let("OpenAI o1 models".freeze, String)
  COPILOT_O3 = T.let("OpenAI o3-mini".freeze, String)
  COPILOT_O_FF = T.let("OpenAI GPT-4.5 model".freeze, String)
  COPILOT_O_FM = T.let("OpenAI o4-mini".freeze, String)
  COPILOT_O_F = T.let("TEMP O_F".freeze, String)
  COPILOT_O_T = T.let("OpenAI o3".freeze, String)
  COPILOT_OFO = T.let("OpenAI GPT-4.1".freeze, String)
  EDITOR_PREVIEW_FEATURES = T.let("Editor preview features".freeze, String)
  AUTOMATIC_CODE_REVIEW = T.let("Automatic Copilot code review".freeze, String)
  DOTCOM_PREVIEW_FEATURES = T.let("Copilot in GitHub.com (preview features)".freeze, String)
  COPILOT_WORKSPACE_FOR_EMU = T.let("Copilot Workspace".freeze, String)
  COPILOT_DESKTOP = T.let("Copilot in GitHub Desktop".freeze, String)
  COPILOT_PUBLIC_CODE_SUGGESTIONS = T.let("Copilot Public Code Suggestions".freeze, String)
  COPILOT_PUBLIC_CODE_SUGGESTIONS_UI = T.let("Suggestions matching public code (duplication detection filter)".freeze, String)
  COPILOT_PR_SUMMARIZATIONS = T.let("Copilot for Pull Requests Summarization".freeze, String)
  COPILOT_CONTENT_EXCLUSION = T.let("Copilot Content Exclusion".freeze, String)
  COPILOT_FINETUNING = T.let("Copilot Fine-tuning".freeze, String)

  # Product Pricing
  COPILOT_BUSINESS_MONTHLY_BASE_PRICE = T.let(19, Integer)
  COPILOT_ENTERPRISE_MONTHLY_BASE_PRICE = T.let(39, Integer)
  COPILOT_PRO_MONTHLY_BASE_PRICE = T.let(10, Integer)
  COPILOT_PRO_YEARLY_BASE_PRICE = T.let(100, Integer)
  COPILOT_PRO_PLUS_MONTHLY_BASE_PRICE = T.let(39, Integer)
  COPILOT_PRO_PLUS_YEARLY_BASE_PRICE = T.let(390, Integer)

  # API endpiont forbidden messages (message returned with 403)
  ORG_OR_ENTERPRISE_ADMIN_FORBID_MESSAGE = T.let("You must have admin rights to the organization or the parent enterprise.", String)
  ORG_ADMIN_FORBID_MESSAGE = T.let("You must have admin rights to the organization.", String)
  ENTERPRISE_ADMIN_FORBID_MESSAGE = T.let("You must have admin or billing manager rights to the enterprise", String)

  # Code Review
  COPILOT_CODE_REVIEW_DOCUMENTATION = T.let("https://docs.github.com/en/enterprise-cloud@latest/copilot/using-github-copilot/code-review/using-copilot-code-review", String)
  CODE_REVIEW_DOCS_URL = T.let("https://gh.io/copilot-code-review-docs", String)
  CODE_REVIEW_REQUEST_DOCS_URL = T.let("https://gh.io/copilot-code-review-docs?tool=webui#requesting-a-review-from-copilot", String)
  CODE_REVIEW_AUTOMATIC_DOCS_URL = T.let("https://gh.io/copilot-code-review-docs?tool=webui#enabling-automatic-reviews-from-copilot", String)
  CODE_REVIEW_CONFIGURING_AUTO_DOCS_URL = T.let("https://docs.github.com/en/copilot/using-github-copilot/code-review/configuring-automatic-code-review-by-copilot", String)
  CODE_REVIEW_VS_CODE_DOCS_URL = T.let("https://gh.io/copilot-code-review-docs?tool=vscode", String)
  CODE_REVIEW_DISCUSSION_URL = T.let("https://gh.io/copilot-code-review-discussion", String)

  WORKSPACE_FOR_PRS_DOCS_URL = T.let("https://docs.github.com/en/copilot/using-github-copilot/using-github-copilot-for-pull-requests/using-copilot-to-help-you-work-on-a-pull-request", String)

  # Copilot SWE Agent
  SWE_AGENT_DISPLAY_NAME_SHORT = T.let("Coding agent".freeze, String)
  COPILOT_SWE_AGENT = T.let("Copilot coding agent".freeze, String)

  MICROSOFT_PRIVACY_STATEMENT_URL = T.let("https://privacy.microsoft.com/en-us/privacystatement".freeze, String)

  sig { returns(String) }
  def self.individual_product_name
    INDIVIDUAL_PRO_PRODUCT_NAME
  end

  sig { returns(String) }
  def self.individual_pro_product_name
    INDIVIDUAL_PRO_PRODUCT_NAME
  end

  sig { returns(String) }
  def self.individual_pro_plus_product_name
    INDIVIDUAL_PRO_PLUS_PRODUCT_NAME
  end

  sig { returns(String) }
  def self.individual_free_product_name
    INDIVIDUAL_FREE_PRODUCT_NAME
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

    Recent activity on your account has caught the attention of our abuse-detection systems. This activity may have included use of Copilot via scripted interactions, an otherwise deliberately unusual or strenuous nature, or use of multiple accounts to circumvent usage limits.

    While we have not yet restricted Copilot access for your account, further anomalous activity could result in a temporary suspension of your Copilot access.

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

    Recent activity on your account has caught the attention of our abuse-detection systems. This activity may have included use of Copilot via scripted interactions, an otherwise deliberately unusual or strenuous nature, or use of multiple accounts to circumvent usage limits.

    Due to this, we have suspended your access to Copilot.

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

  sig { returns(::Redis) }
  def self.activity_redis
    @copilot_activity_redis ||= T.let(::Redis.new(GitHub.read_redis_config("config/redis_copilot_activity.yml", connect_timeout: 0.2)), T.nilable(::Redis))
  end

  # DEPRECATED: This should not be used and all calls should go through the Twirp client at lib/copilot_limiter
  sig { returns(::Redis) }
  def self.limiter_redis
    @copilot_limiter_redis ||= T.let(::Redis.new(GitHub.read_redis_config("config/redis_copilot_limiter.yml", connect_timeout: 0.2)), T.nilable(::Redis))
  end

  sig { returns(String) }
  def self.github_general_privacy_statement_url
    DocsUrlConfig.url_for("site-policy/github-general-privacy-statement")
  end
end
