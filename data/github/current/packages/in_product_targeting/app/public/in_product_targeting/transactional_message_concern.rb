# typed: strict
# frozen_string_literal: true

module InProductTargeting
  module TransactionalMessageConcern
    extend ActiveSupport::Concern

    # Pages where global messages should also render in page-specific location
    GLOBAL_MESSAGE_INLINE_PAGES = T.let([:agents, :spaces, :copilot].freeze, T::Array[Symbol])

    # Page-keys for non-global configs map 1:1 to a view hook in app/views.
    # Today's hooks:
    #   :dashboard         dashboard/_banners_above_the_header.html.erb
    #   :org               orgs/_index_header.html.erb
    #   :enterprise        businesses/show.html.erb (enterprise overview only)
    #   :enterprise_layout businesses/_layout.html.erb (every /enterprises/{slug}/* page)
    # The page symbol also serializes to `analytics.location`.

    # Context for eligibility checks - provides organization/enterprise/repository when available
    class EligibilityContext < T::Struct
      const :organization, T.nilable(Organization), default: nil
      const :enterprise, T.nilable(Business), default: nil
      const :repository, T.nilable(Repository), default: nil
    end

    # Configuration struct for a transactional message segment
    class MessageSegment < T::Struct
      const :type, Symbol # :text or :link
      const :content, String
      const :href, T.nilable(String), default: nil
      # Optional builder proc that returns the link href for the given EligibilityContext.
      # Takes precedence over `href:` when present. Do not interpolate untrusted strings
      # into the returned URL. Consumed by to_segments_array (React payload path) only.
      const :href_builder, T.nilable(T.proc.params(context: EligibilityContext).returns(String)), default: nil
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
      # Context provides organization/enterprise/repository when available (e.g., on org/enterprise/repo pages)
      # If nil, message is shown to all users (after feature flag and dismissal checks)
      const :eligibility_check, T.nilable(T.proc.params(user: User, context: EligibilityContext).returns(T::Boolean)), default: nil
      # Optional call-to-action button label rendered alongside the message segments.
      # Both cta_label AND cta_href_builder must be present for the CTA to render; if either
      # is nil the payload omits the `cta` field entirely.
      const :cta_label, T.nilable(String), default: nil
      # Optional builder proc that returns the CTA href for the given EligibilityContext.
      # Do not interpolate untrusted strings into the returned URL. Both cta_label AND
      # cta_href_builder must be present for the CTA to render.
      const :cta_href_builder, T.nilable(T.proc.params(context: EligibilityContext).returns(String)), default: nil
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

      # Convert segments to array format for React components.
      # Accepts EligibilityContext so segments declaring an href_builder can resolve
      # their per-request href; static-href segments ignore the context argument.
      sig { params(context: EligibilityContext).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def to_segments_array(context = EligibilityContext.new)
        segments.map do |segment|
          if segment.type == :link
            href_builder = segment.href_builder
            href = href_builder.present? ? href_builder.call(context) : segment.href
            { type: "link", content: segment.content, href: href }
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
    # Active window for the Code Quality upcoming-charges banners. The start gate
    # runs in cq_audience_excluded? with a Rails.env.development? bypass so the
    # banner is reachable in dev before the campaign opens. The end gate is the
    # CI safety anchor; see https://github.com/github/availability/issues/5248.
    CQ_ACTIVE_START = T.let(Date.new(2026, 6, 8), Date)
    CQ_ACTIVE_END = T.let(Date.new(2026, 7, 20), Date)

    # Shared exclusion gate for the Code Quality upcoming-charges banners.
    # Combines the active-window check with the campaign exclusions; cheap
    # checks first.
    sig { params(user: User, business: T.nilable(Business)).returns(T::Boolean) }
    def self.cq_audience_excluded?(user, business)
      today = Time.now.utc.to_date
      return true if today < CQ_ACTIVE_START && !Rails.env.development?
      return true if today >= CQ_ACTIVE_END
      return true if GitHub.multi_tenant_enterprise?
      return true if GitHub.enterprise?
      return true if user.is_enterprise_managed?
      return false if business.nil?
      # Inline copy of NudgeConcern#is_business_in_active_dfd_trial? — that
      # helper is an instance method on a sibling concern; this is a class method.
      return true if business.dfd_trial? && business.trial_expires_at && business.trial_expires_at >= Time.current && business.no_trial_or_active_trial?
      return true if business.trial_expired?
      false
    end

    # True if any repo in the org has Code Quality enabled. Backs the org
    # audience eligibility check: fire only for orgs actively using CQ, not
    # orgs whose enterprise policy permits enablement. Bounded to the first
    # 100 repos (default Rails ordering, id ASC) so the worst-case render
    # path (org with CQ on none of the scanned repos) stays bounded; each
    # check is a synchronous Turboscan RPC. Cached 1hr per org.
    sig { params(organization: Organization).returns(T::Boolean) }
    def self.cq_org_has_active_repo?(organization)
      Rails.cache.fetch("ipm550_cq_org_has_active_repo/#{organization.id}", expires_in: 1.hour) do
        organization.repositories.limit(100).any? do |repo|
          CodeQuality.enabled?(repo, raise_on_error: false)
        end
      end
    end

    PRODUCTION_TRANSACTIONAL_MESSAGES = T.let([
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

      # Code Quality upcoming-charges banners — registry order is priority, so an
      # enterprise owner who is also an org admin sees the enterprise banner.
      # Active-window enforcement lives in cq_audience_excluded?; the engine's
      # `effective_date` and `hide_from_new_user` fields are set to neutral values
      # so they do not double-gate the helper-owned date logic. The
      # :enterprise_layout page-key fires the enterprise banner on every
      # /enterprises/{slug}/* page (see app/views/businesses/_layout.html.erb).
      TransactionalMessageConfig.new(
        nudge_id: :ipm_code_quality_upcoming_charges_enterprise,
        nudge_category: "ipm_code_quality_upcoming_charges_enterprise",
        global: false,
        feature_flag: :general_ipm_code_quality_upcoming_charges,
        pages: { enterprise_layout: true },
        effective_date: "2025-01-01",
        hide_from_new_user: false,
        segments: [
          MessageSegment.new(type: :text, content: "Code Quality becomes generally available on July 20 with a base subscription plus usage-based billing. Use "),
          MessageSegment.new(type: :link, content: "enterprise policies", href_builder: ->(context) {
            "/enterprises/#{context.enterprise.slug}/settings/code_quality_policies"
          }),
          MessageSegment.new(type: :text, content: " to govern which organizations can enable it. "),
          MessageSegment.new(type: :link, content: "See pricing", href: "https://docs.github.com/billing/concepts/product-billing/github-code-quality"),
          MessageSegment.new(type: :text, content: "."),
        ],
        cta_label: "Learn more",
        cta_href_builder: ->(_context) {
          "https://docs.github.com/code-security/concepts/about-code-quality"
        },
        eligibility_check: ->(user, context) {
          business = context.enterprise
          return false if business.nil?
          return false if cq_audience_excluded?(user, business)
          # Only show for enterprises that have CQ policy enabled (not set to "none").
          return false if CodeQualityAccessPolicyConfig.new(business).no_members_can_enable_code_quality?
          business.owner?(user) || business.billing_manager?(user)
        },
      ),

      TransactionalMessageConfig.new(
        nudge_id: :ipm_code_quality_upcoming_charges_org,
        nudge_category: "ipm_code_quality_upcoming_charges_org",
        global: true,
        feature_flag: :general_ipm_code_quality_upcoming_charges,
        pages: {},
        effective_date: "2025-01-01",
        hide_from_new_user: false,
        segments: [
          MessageSegment.new(type: :text, content: "Code Quality becomes generally available on July 20 with a base subscription plus usage-based billing for AI-powered work. Your analysis continues. "),
          MessageSegment.new(type: :link, content: "Review enablement", href_builder: ->(context) {
            "/organizations/#{context.organization.display_login}/settings/code-quality"
          }),
          MessageSegment.new(type: :text, content: " and "),
          MessageSegment.new(type: :link, content: "pricing", href: "https://docs.github.com/billing/concepts/product-billing/github-code-quality"),
          MessageSegment.new(type: :text, content: " before then."),
        ],
        cta_label: "Learn more",
        cta_href_builder: ->(_context) {
          "https://docs.github.com/code-security/concepts/about-code-quality"
        },
        eligibility_check: ->(user, context) {
          organization = context.organization
          return false if organization.nil?
          # Enterprise-owned orgs are covered by the enterprise banner on
          # /enterprises/{slug}/* pages; this targets Team-plan orgs only.
          return false if organization.business.present?
          return false if cq_audience_excluded?(user, organization.business)
          return false unless organization.admin_ids.include?(user.id)
          # Fire only for orgs actively using Code Quality.
          cq_org_has_active_repo?(organization)
        },
      ),

      TransactionalMessageConfig.new(
        nudge_id: :ipm_code_quality_upcoming_charges_repo,
        nudge_category: "ipm_code_quality_upcoming_charges_repo",
        global: true,
        feature_flag: :general_ipm_code_quality_upcoming_charges,
        pages: {},
        effective_date: "2025-01-01",
        hide_from_new_user: false,
        segments: [
          MessageSegment.new(type: :text, content: "Code Quality becomes generally available on July 20 and transitions to a paid product. Your analysis continues. You can manage enablement from "),
          MessageSegment.new(type: :link, content: "repository settings", href_builder: ->(context) {
            "/#{context.repository.name_with_display_owner}/settings/code-quality"
          }),
          MessageSegment.new(type: :text, content: ". "),
          MessageSegment.new(type: :link, content: "See pricing", href: "https://docs.github.com/billing/concepts/product-billing/github-code-quality"),
          MessageSegment.new(type: :text, content: "."),
        ],
        cta_label: "Learn more",
        cta_href_builder: ->(_context) {
          "https://docs.github.com/code-security/concepts/about-code-quality"
        },
        eligibility_check: ->(user, context) {
          repository = context.repository
          return false if repository.nil?
          owner = repository.owner
          organization = owner.is_a?(Organization) ? owner : nil
          return false if cq_audience_excluded?(user, organization&.business)
          return false unless repository.adminable_by?(user)
          return false unless CodeQuality.enabled?(repository, raise_on_error: false)
          # Repo admins who are also org admins see the org banner (higher priority in the
          # registry), so this banner suppresses itself to avoid showing them two banners.
          return false if organization && organization.admin_ids.include?(user.id)
          true
        },
      ),

    ].freeze, T::Array[TransactionalMessageConfig])

    # --- Test messages for page-specific transactional banners (non-global) ---
    # These test the React partial migration on each surface.
    # Each has its own feature flag so it can be toggled independently.
    # To add a new test banner, add an entry here and update the setup script
    # (feature flags, test accounts) and QA docs in script/in-product-messaging/qa/.
    TEST_TRANSACTIONAL_MESSAGES = T.let([
      TransactionalMessageConfig.new(
        nudge_id: :ipm_test_transactional_banner_dashboard,
        nudge_category: "ipm_test_transactional_banner_dashboard",
        global: false,
        feature_flag: :ipm_test_transactional_banner_dashboard,
        pages: { dashboard: true },
        effective_date: "2026-03-25",
        hide_from_new_user: false,
        segments: [
          MessageSegment.new(type: :text, content: "This is a test transactional banner on the dashboard. "),
          MessageSegment.new(type: :link, content: "Learn more", href: "https://github.com/features"),
          MessageSegment.new(type: :text, content: "."),
        ],
        eligibility_check: ->(_user, _context) { true },
      ),
      TransactionalMessageConfig.new(
        nudge_id: :ipm_test_transactional_banner_org,
        nudge_category: "ipm_test_transactional_banner_org",
        global: false,
        feature_flag: :ipm_test_transactional_banner_org,
        pages: { org: true },
        effective_date: "2026-03-25",
        hide_from_new_user: false,
        segments: [
          MessageSegment.new(type: :text, content: "This is a test transactional banner on the org page. "),
          MessageSegment.new(type: :link, content: "Learn more", href: "https://github.com/features"),
          MessageSegment.new(type: :text, content: "."),
        ],
        eligibility_check: ->(_user, _context) { true },
      ),
      TransactionalMessageConfig.new(
        nudge_id: :ipm_test_transactional_banner_enterprise,
        nudge_category: "ipm_test_transactional_banner_enterprise",
        global: false,
        feature_flag: :ipm_test_transactional_banner_enterprise,
        pages: { enterprise: true },
        effective_date: "2026-03-25",
        hide_from_new_user: false,
        segments: [
          MessageSegment.new(type: :text, content: "This is a test transactional banner on the enterprise page. "),
          MessageSegment.new(type: :link, content: "Learn more", href: "https://github.com/features"),
          MessageSegment.new(type: :text, content: "."),
        ],
        eligibility_check: ->(_user, _context) { true },
      ),
      TransactionalMessageConfig.new(
        nudge_id: :ipm_test_transactional_banner_copilot,
        nudge_category: "ipm_test_transactional_banner_copilot",
        global: false,
        feature_flag: :ipm_test_transactional_banner_copilot,
        pages: { copilot: true },
        effective_date: "2026-03-25",
        hide_from_new_user: false,
        segments: [
          MessageSegment.new(type: :text, content: "This is a test transactional banner on the copilot page. "),
          MessageSegment.new(type: :link, content: "Learn more", href: "https://github.com/features"),
          MessageSegment.new(type: :text, content: "."),
        ],
        eligibility_check: ->(_user, _context) { true },
      ),
      TransactionalMessageConfig.new(
        nudge_id: :ipm_test_transactional_banner_spaces,
        nudge_category: "ipm_test_transactional_banner_spaces",
        global: false,
        feature_flag: :ipm_test_transactional_banner_spaces,
        pages: { spaces: true },
        effective_date: "2026-03-25",
        hide_from_new_user: false,
        segments: [
          MessageSegment.new(type: :text, content: "This is a test transactional banner on the spaces page. "),
          MessageSegment.new(type: :link, content: "Learn more", href: "https://github.com/features"),
          MessageSegment.new(type: :text, content: "."),
        ],
        eligibility_check: ->(_user, _context) { true },
      ),
      TransactionalMessageConfig.new(
        nudge_id: :ipm_test_transactional_banner_agents,
        nudge_category: "ipm_test_transactional_banner_agents",
        global: false,
        feature_flag: :ipm_test_transactional_banner_agents,
        pages: { agents: true },
        effective_date: "2026-03-25",
        hide_from_new_user: false,
        segments: [
          MessageSegment.new(type: :text, content: "This is a test transactional banner on the agents page. "),
          MessageSegment.new(type: :link, content: "Learn more", href: "https://github.com/features"),
          MessageSegment.new(type: :text, content: "."),
        ],
        eligibility_check: ->(_user, _context) { true },
      ),
      TransactionalMessageConfig.new(
        nudge_id: :ipm_test_transactional_banner_issues,
        nudge_category: "ipm_test_transactional_banner_issues",
        global: false,
        feature_flag: :ipm_test_transactional_banner_issues,
        pages: { issues: true },
        effective_date: "2026-03-25",
        hide_from_new_user: false,
        segments: [
          MessageSegment.new(type: :text, content: "This is a test transactional banner on the issues page. "),
          MessageSegment.new(type: :link, content: "Learn more", href: "https://github.com/features"),
          MessageSegment.new(type: :text, content: "."),
        ],
        eligibility_check: ->(_user, _context) { true },
      ),
      TransactionalMessageConfig.new(
        nudge_id: :ipm_test_transactional_banner_prs,
        nudge_category: "ipm_test_transactional_banner_prs",
        global: false,
        feature_flag: :ipm_test_transactional_banner_prs,
        pages: { prs: true },
        effective_date: "2026-03-25",
        hide_from_new_user: false,
        segments: [
          MessageSegment.new(type: :text, content: "This is a test transactional banner on the pull requests page. "),
          MessageSegment.new(type: :link, content: "Learn more", href: "https://github.com/features"),
          MessageSegment.new(type: :text, content: "."),
        ],
        eligibility_check: ->(_user, _context) { true },
      ),
      TransactionalMessageConfig.new(
        nudge_id: :ipm_test_transactional_banner_repos,
        nudge_category: "ipm_test_transactional_banner_repos",
        global: false,
        feature_flag: :ipm_test_transactional_banner_repos,
        pages: { repo: true },
        effective_date: "2026-03-25",
        hide_from_new_user: false,
        segments: [
          MessageSegment.new(type: :text, content: "This is a test transactional banner on the repository page. "),
          MessageSegment.new(type: :link, content: "Learn more", href: "https://github.com/features"),
          MessageSegment.new(type: :text, content: "."),
        ],
        eligibility_check: ->(_user, _context) { true },
      ),
    ].freeze, T::Array[TransactionalMessageConfig])

    # Combined registry: production messages first (higher priority), then test messages
    TRANSACTIONAL_MESSAGES = T.let(
      (PRODUCTION_TRANSACTIONAL_MESSAGES + TEST_TRANSACTIONAL_MESSAGES).freeze,
      T::Array[TransactionalMessageConfig],
    )

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

      build_payload_from_config(config, page, view_context, context)
    end

    # Build the payload for global transactional messages (shown on all pages)
    sig { params(user: User, view_context: T.untyped, context: EligibilityContext).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def global_transactional_message_payload(user, view_context, context = EligibilityContext.new)
      config = global_transactional_message(user, context)
      return nil unless config

      build_payload_from_config(config, :global, view_context, context)
    end

    # Convenience wrapper for producers that have a nilable organization/repository
    # in hand but don't want to know how IPM derives the enterprise from them.
    # Encapsulates the enterprise-derivation rule (org's business, else repository
    # owner's business) so producers stay out of IPM scope semantics.
    sig do
      params(
        user: User,
        view_context: T.untyped,
        organization: T.nilable(Organization),
        repository: T.nilable(Repository),
      ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
    end
    def global_transactional_message_payload_for_scope(user, view_context, organization: nil, repository: nil)
      context = EligibilityContext.new(
        organization: organization,
        enterprise: organization&.business || repository&.owner&.business,
        repository: repository,
      )
      global_transactional_message_payload(user, view_context, context)
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
    sig { params(config: TransactionalMessageConfig, location: Symbol, view_context: T.untyped, context: EligibilityContext).returns(T::Hash[Symbol, T.untyped]) }
    def build_payload_from_config(config, location, view_context, context = EligibilityContext.new)
      dismiss_params = { nudge: true }
      dismiss_params[:group] = config.nudge_group.to_s if config.nudge_group.present?

      payload = T.let({
        segments: config.to_segments_array(context),
        dismissPath: view_context.dismiss_notice_path(config.nudge_id.to_s, dismiss_params),
        # Analytics metadata for React component
        analytics: {
          category: config.nudge_category,
          group: config.nudge_group.to_s,
          location: location.to_s,
        },
      }, T::Hash[Symbol, T.untyped])

      # Emit top-level CTA only when BOTH label and href-builder are present.
      # A partial config (one set, the other nil) is silently treated as no-CTA so a
      # half-rendered button never reaches the wire.
      cta_label = config.cta_label
      cta_href_builder = config.cta_href_builder
      if cta_label.present? && cta_href_builder.present?
        payload[:cta] = { label: cta_label, href: cta_href_builder.call(context) }
      end

      payload
    end
  end
end
