# typed: strict
# frozen_string_literal: true

module InProductTargeting
  module TransactionalMessageConcern
    extend ActiveSupport::Concern

    # Pages where global messages should also render in page-specific location
    GLOBAL_MESSAGE_INLINE_PAGES = T.let([:agents, :spaces, :copilot].freeze, T::Array[Symbol])

    # Configuration struct for a transactional message segment
    class MessageSegment < T::Struct
      const :type, Symbol # :text or :link
      const :content, String
      const :href, T.nilable(String), default: nil
    end

    # Context for eligibility checks - provides organization/enterprise when available
    class EligibilityContext < T::Struct
      const :organization, T.nilable(Organization), default: nil
      const :enterprise, T.nilable(Business), default: nil
    end

    # Configuration struct for a transactional message
    class TransactionalMessageConfig < T::Struct
      const :nudge_id, Symbol
      const :nudge_category, String
      const :nudge_group, T.nilable(Symbol), default: nil
      const :segments, T::Array[MessageSegment]
      const :feature_flag, Symbol
      const :pages, T::Hash[Symbol, T::Boolean] # { dashboard: true, repo: false }
      # Eligibility check - proc that takes a User and EligibilityContext, returns true if user is eligible
      # Context provides organization/enterprise when available (e.g., on org/enterprise pages)
      # If nil, message is shown to all users (after feature flag and dismissal checks)
      const :eligibility_check, T.nilable(T.proc.params(user: User, context: EligibilityContext).returns(T::Boolean)), default: nil
      # Date when the notice becomes effective (format: "YYYY-MM-DD", used for hide_from_new_user logic)
      const :effective_date, String
      # If true, users created after effective_date won't see this notice
      const :hide_from_new_user, T::Boolean, default: false
      # If true, message is shown on all logged-in pages (full-width banner at top of page)
      const :global, T::Boolean, default: false

      # Check if this message should show on a given page
      sig { params(page: Symbol).returns(T::Boolean) }
      def show_on_page?(page)
        # Global messages should only render in the global location,
        # except for agents, spaces, and copilot pages where they should also render inline
        if global
          return GLOBAL_MESSAGE_INLINE_PAGES.include?(page)
        end

        pages.fetch(page, false)
      end

      # Convert segments to HTML string for Rails views
      sig { params(view_context: T.untyped).returns(String) }
      def to_html(view_context)
        html_parts = segments.map do |segment|
          case segment.type
          when :link
            view_context.link_to(segment.content, segment.href, class: "Link--inTextBlock")
          else
            segment.content
          end
        end
        html_parts.join.html_safe # rubocop:disable Rails/OutputSafety
      end

      # Convert segments to array format for React components
      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def to_segments_array
        segments.map do |segment|
          if segment.type == :link
            { type: "link", content: segment.content, href: segment.href }
          else
            { type: "text", content: segment.content }
          end
        end
      end
    end

    # Registry of all transactional messages
    # Priority is determined by array order - first message in array has highest priority
    #
    # EXAMPLE: How to add a new transactional message
    # ================================================
    # TransactionalMessageConfig.new(
    #   nudge_id: :my_new_message_nudge,              # Unique ID for dismissal tracking
    #   nudge_category: "my_message_category",        # Analytics category
    #   global: false,                                # true = full-width banner on all pages
    #   feature_flag: :my_new_message_feature_flag,   # Must also register in application_layout_features.rb
    #   pages: {                                      # Which pages to show on (ignored if global: true)
    #     dashboard: false,
    #     repo: false,
    #     copilot: false,
    #     agents: false,
    #     spaces: false,
    #     issues: false,
    #     prs: false,
    #     org: false,
    #     enterprise: false,
    #   },
    #   effective_date: "2026-03-01",                 # Message won't show before this date
    #   hide_from_new_user: false,                    # If true, users created after effective_date won't see it
    #   segments: [                                   # Message content (allows mixing text and links)
    #     MessageSegment.new(type: :text, content: "Your message text here. "),
    #     MessageSegment.new(type: :link, content: "Link text", href: "https://example.com"),
    #     MessageSegment.new(type: :text, content: "."),
    #   ],
    #   eligibility_check: ->(user, context) {        # Optional: custom eligibility logic
    #     # context.organization and context.enterprise available when on those pages
    #     user.some_condition?
    #   },
    # ),
    #
    TRANSACTIONAL_MESSAGES = T.let([
      TransactionalMessageConfig.new(
        nudge_id: :ipm_global_banner_test,
        nudge_category: "ipm_global_banner_test",
        global: true,
        # Feature flag must also be registered in app/controllers/application_controller/application_layout_features.rb
        feature_flag: :ipm_global_banner_test,
        pages: { dashboard: false, repo: false },
        effective_date: "2026-01-27",
        hide_from_new_user: false,
        # We take this approach to allow for message construction in react without requiring dangerouslySetInnerHTML
        segments: [
          MessageSegment.new(type: :text, content: "This is a test message for the global banner. "),
          MessageSegment.new(type: :link, content: "Review this update", href: "https://gh.io/AAzfaht"),
        ],
        eligibility_check: ->(_user, _context) { true },
      ),
      TransactionalMessageConfig.new(
        nudge_id: :dashboard_jan_2026_privacy_copilot_nudge,
        nudge_category: "copilot_privacy_update_jan_2026",
        global: false,
        # Feature flag must also be registered in app/controllers/application_controller/application_layout_features.rb
        feature_flag: :dashboard_jan_2026_privacy_copilot_nudge,
        pages: { dashboard: true, repo: true },
        effective_date: "2026-01-27",
        hide_from_new_user: false,
        # We take this approach to allow for message construction in react without requiring dangerouslySetInnerHTML
        segments: [
          MessageSegment.new(type: :text, content: "On April 3 we'll start using GitHub Copilot interaction data for AI model training unless you opt out. "),
          MessageSegment.new(type: :link, content: "Review this update", href: "https://gh.io/AAzfaht"),
          MessageSegment.new(type: :text, content: " and manage your preferences in your "),
          MessageSegment.new(type: :link, content: "GitHub account settings", href: "https://github.com/settings/copilot/features"),
          MessageSegment.new(type: :text, content: "."),
        ],
        eligibility_check: ->(user, _context) {
          copilot_user = Copilot::Public::User.new(user)
          copilot_user.has_pro_plus_access? ||
            copilot_user.has_limited_access? ||
            copilot_user.has_pro_access? ||
            copilot_user.has_free_pro_access?
        },
      ),
    ].freeze, T::Array[TransactionalMessageConfig])

    # Register all transactional message notices with UserNotice
    # This allows dismissal tracking without requiring notices.yml entries
    TRANSACTIONAL_MESSAGES.each do |config|
      UserNotice.register(
        "name" => config.nudge_id.to_s,
        "effective_date" => config.effective_date,
        "hide_from_new_user" => config.hide_from_new_user,
      )
    end

    # Master feature flag for all transactional messages
    MASTER_FEATURE_FLAG = :in_product_messaging_transactional_message_engine

    # Get the highest priority transactional message for a user on a given page
    # Messages are checked in array order - first eligible message is returned
    # Returns nil if a global message is already being shown (to avoid duplicate banners),
    # except for agents, spaces, and copilot pages where global messages render inline
    #
    # PERFORMANCE: Checks are ordered from cheapest to most expensive:
    # 1. Page check (show_on_page?) - very cheap array lookup
    # 2. Feature flags and dismissal - cheap/moderate
    # 3. Eligibility checks - expensive (done last via should_show_transactional_message?)
    sig { params(user: User, page: Symbol, context: EligibilityContext).returns(T.nilable(TransactionalMessageConfig)) }
    def transactional_message_for_page(user, page, context = EligibilityContext.new)
      return nil unless transactional_messages_enabled?(user)

      find_transactional_message_for_page(user, page, context)
    end

    sig { params(user: User, page: Symbol, context: EligibilityContext).returns(T.nilable(TransactionalMessageConfig)) }
    def find_transactional_message_for_page(user, page, context = EligibilityContext.new)
      start_time = GitHub::Dogstats.monotonic_time

      # If there's an active global message, don't show page-specific banners
      # This prevents duplicate banners on the same page
      # Exception: agents, spaces, and copilot pages render global messages inline
      # Use quick check first to avoid expensive eligibility checks when possible
      unless GLOBAL_MESSAGE_INLINE_PAGES.include?(page)
        return nil if global_message_might_show?(user) && find_global_transactional_message(user, context).present?
      end

      # Find the first eligible message for this page (array order = priority)
      # show_on_page? is checked first (cheap) before should_show_transactional_message? (expensive)
      message = TRANSACTIONAL_MESSAGES.find do |msg|
        msg.show_on_page?(page) && should_show_transactional_message?(user, msg, context)
      end

      # Record timing for eligibility checks - this runs whenever the master flag is enabled
      # and helps track performance impact on page load time
      record_transactional_message_timing(start_time, page)

      message
    end

    # Get the highest priority global transactional message for a user
    # Global messages are shown on all logged-in pages as a full-width banner
    # Messages are checked in array order - first eligible global message is returned
    sig { params(user: User, context: EligibilityContext).returns(T.nilable(TransactionalMessageConfig)) }
    def global_transactional_message(user, context = EligibilityContext.new)
      return nil unless transactional_messages_enabled?(user)

      find_global_transactional_message(user, context)
    end

    sig { params(user: User, context: EligibilityContext).returns(T.nilable(TransactionalMessageConfig)) }
    def find_global_transactional_message(user, context = EligibilityContext.new)
      start_time = GitHub::Dogstats.monotonic_time

      # Find the first eligible global message (array order = priority)
      # msg.global is checked first (cheap) before should_show_transactional_message? (expensive)
      message = TRANSACTIONAL_MESSAGES.find do |msg|
        msg.global && should_show_transactional_message?(user, msg, context)
      end

      # Record timing for eligibility checks - this runs whenever the master flag is enabled
      # and helps track performance impact on page load time
      record_transactional_message_timing(start_time, :global)

      message
    end

    # Quick check if any global message might potentially show (without running expensive eligibility checks)
    # Used to short-circuit and avoid running full eligibility checks when no global messages are configured
    sig { params(user: User).returns(T::Boolean) }
    def global_message_might_show?(user)
      TRANSACTIONAL_MESSAGES.any? do |msg|
        next false unless msg.global

        # Only check cheap conditions - skip eligibility check
        effective_date = Date.parse(msg.effective_date)
        next false if Date.current < effective_date
        next false unless user.feature_flag_enabled?(msg.feature_flag, default: false)
        next false if user.dismissed_notice?(msg.nudge_id.to_s)

        true
      end
    end

    # Check if transactional messages are globally enabled
    sig { params(user: User).returns(T::Boolean) }
    def transactional_messages_enabled?(user)
      # Usually we exclude proxima for in product messages and exclude users who opted out but that's only what we do
      # for marketing purposes. Transactional messages need to be shown to proxima accounts and all users even those who are opted out
      # need to be shown transactional messages.

      # Don't show on GitHub Enterprise Server installations
      return false if GitHub.enterprise?

      # Don't show for enterprise-managed users
      return false if user.is_enterprise_managed?

      # Master feature flag - if disabled, no transactional messages show
      user.feature_flag_enabled?(MASTER_FEATURE_FLAG, default: false)
    end

    # Check if a specific transactional message should be shown to a user
    # IMPORTANT: Checks are ordered from cheapest to most expensive for performance
    # 1. Effective date (cheap - date comparison)
    # 2. Feature flag (cheap - cached flag lookup)
    # 3. Dismissed notice (moderate - DB lookup, usually cached)
    # 4. Eligibility check (expensive - may involve API calls, DB queries)
    sig { params(user: User, config: TransactionalMessageConfig, context: EligibilityContext).returns(T::Boolean) }
    def should_show_transactional_message?(user, config, context = EligibilityContext.new)
      # 1. Cheap: Don't show message before its effective date
      effective_date = Date.parse(config.effective_date)
      return false if Date.current < effective_date

      # 2. Cheap: Check feature flag
      return false unless user.feature_flag_enabled?(config.feature_flag, default: false)

      # 3. Moderate: Check if user has dismissed this message
      return false if user.dismissed_notice?(config.nudge_id.to_s)

      # 4. Expensive (LAST): Check message-specific eligibility via the configured proc
      eligibility_check = config.eligibility_check
      return eligibility_check.call(user, context) if eligibility_check.present?

      # No eligibility check configured - show to all users
      true
    end

    # Build the payload for React components
    sig { params(user: User, page: Symbol, view_context: T.untyped, context: EligibilityContext).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def transactional_message_payload(user, page, view_context, context = EligibilityContext.new)
      config = transactional_message_for_page(user, page, context)
      return nil unless config

      build_payload_from_config(config, page, view_context)
    end

    # Build the payload for global transactional messages (shown on all pages)
    sig { params(user: User, view_context: T.untyped, context: EligibilityContext).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def global_transactional_message_payload(user, view_context, context = EligibilityContext.new)
      config = global_transactional_message(user, context)
      return nil unless config

      build_payload_from_config(config, :global, view_context)
    end

    private

    # Record timing metrics for transactional message computation
    # This helps track performance impact of the transactional message engine across different pages
    sig { params(start_time: Float, page: Symbol).void }
    def record_transactional_message_timing(start_time, page)
      duration_ms = GitHub::Dogstats.duration(start_time)
      tags = [
        "page:#{page}",
      ]
      GitHub.dogstats.distribution("in_product_messaging.transactional_message.timing", duration_ms, tags: tags)
    end

    # Build the common payload structure from a config
    sig { params(config: TransactionalMessageConfig, location: Symbol, view_context: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
    def build_payload_from_config(config, location, view_context)
      dismiss_params = { nudge: true }
      dismiss_params[:group] = config.nudge_group.to_s if config.nudge_group.present?

      {
        segments: config.to_segments_array,
        dismissPath: view_context.dismiss_notice_path(config.nudge_id.to_s, dismiss_params),
        # Analytics metadata for React component
        analytics: {
          category: config.nudge_category,
          group: config.nudge_group.to_s,
          location: location.to_s,
        },
      }
    end
  end
end
