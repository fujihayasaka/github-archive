# typed: strict
# frozen_string_literal: true

module InProductTargeting
  module Components
    module DashboardNudges
      # Renders the "{business} has enabled Copilot CLI for you" enterprise dashboard
      # nudge as a React partial (BannerNudgeCard), migrated out of the ERB
      # BusinessNudgeComponent variant `:ipm_accelerate_dashboard_business_copilot_cli_enabled`.
      #
      # Eligibility is UNCHANGED: it reuses EnterpriseNudgeConcern's
      # `show_enterprise_dashboard_nudge?`, so the same users see the nudge as before.
      # Only the presentation moves from ERB to React. Follows the TBB precedent
      # (OrganizationBanners::TbbSetupBudgetBannerComponent) of a thin component that
      # builds props and calls `render_react_partial`.
      class CopilotCliEnabledDashboardNudgeComponent < ApplicationComponent
        include ApplicationComponent::Rescuable
        include InProductTargeting::EnterpriseNudgeConcern

        rescue_from StandardError, with: :nothing

        NudgeConfig = InProductTargeting::NudgeConcern::NudgeConfig

        NUDGE_KEY = T.let(:dashboard_copilot_cli_enabled, Symbol)
        # Distinct hydro categories per A|B arm so impressions/clicks/dismissals can be
        # compared in analytics. Control keeps the existing `_nudge_1`; treatment is `_nudge_0`.
        NUDGE_CATEGORY_CONTROL = T.let("ipm_accelerate_dashboard_business_copilot_cli_enabled_nudge_1", String)
        NUDGE_CATEGORY_TREATMENT = T.let("ipm_accelerate_dashboard_business_copilot_cli_enabled_nudge_0", String)
        NUDGE_LOCATION = T.let("dashboard", String)
        CTA_ACTION_CONTROL = T.let("get_started_with_copilot_cli", String)
        CTA_ACTION_TREATMENT = T.let("copy", String)
        # Same asset the ERB variant used.
        ICON_PATH = T.let("modules/dashboard/promos/general/copilot-menu-no-indicator-1746823169.svg", String)
        PARTIAL_NAME = T.let("banner-nudge-card", String)

        # Treatment-only: install methods for the React `CommandPicker` (copy-command UI).
        # Shape matches the `InstallationMethod` interface in github-ui's BannerNudgeCard.
        # `os` drives client-side OS auto-detection; `defaultInstallationMethod: "auto"`
        # selects the OS-appropriate method.
        INSTALL_METHODS = T.let(
          [
            { key: "homebrew", label: "Install with Homebrew", command: "brew install copilot-cli", os: "macos" },
            { key: "winget", label: "Install with WinGet", command: "winget install GitHub.Copilot", os: "windows" },
            { key: "script", label: "Install with script", command: "curl -fsSL https://gh.io/copilot-install | bash", os: "linux" },
            { key: "npm", label: "Install with npm", command: "npm install -g @github/copilot" },
          ].freeze,
          T::Array[T::Hash[Symbol, String]]
        )

        sig { params(business: Business, user: User).void }
        def initialize(business:, user:)
          @business = T.let(business, Business)
          @user = T.let(user, User)
        end

        sig { returns(T.nilable(String)) }
        def call
          return unless render?

          InProductTargeting::NudgeMemory.new(user).save_a_copy_of_impression_analytics_to_dotcom(id: nudge_config.nudge_id, group: nudge_config.nudge_group, enterprise_id: business.id)

          content_tag(:div, class: "tmp-mb-4") do
            render_react_partial(name: PARTIAL_NAME, props: react_props)
          end
        end

        sig { returns(T::Boolean) }
        def render?
          return false if business.suspended?

          show_enterprise_dashboard_nudge?(user, business, NUDGE_KEY)
        end

        # Serializable props passed to the generic React `banner-nudge-card`
        # partial. Extracted from `call` so the copy/CTA/analytics shape can be unit
        # tested directly — `render_react_partial` emits nothing until the github-ui
        # bundle is in the manifest, so the rendered output can't be asserted pre-merge.
        #
        # A|B test (issue #502): the backend owns which variant renders. The concern
        # decides 0 (treatment) vs 1 (control); this component builds the matching props
        # AND hydro category together, so analytics and UI can never drift. The React
        # component is unaware an experiment exists — treatment is purely additive props.
        sig { returns(T::Hash[Symbol, T.untyped]) }
        def react_props
          treatment? ? treatment_react_props : control_react_props
        end

        sig { returns(T::Boolean) }
        def treatment?
          copilot_cli_enabled_dashboard_nudge_variant(user).zero?
        end

        # Control — today's experience, verbatim: a single "Get started with Copilot CLI"
        # CTA that dismisses-and-redirects. Category ends `_nudge_1`.
        sig { returns(T::Hash[Symbol, T.untyped]) }
        def control_react_props
          base_react_props.merge(
            ctaTitle: "Get started with Copilot CLI",
            # This variant uses dismiss-and-redirect (NOT click-and-redirect).
            ctaHref: dismiss_and_redirect_path(
              destination_key: nudge_config.destination_key,
              business_id: business.id,
              notice: nudge_config.nudge_id,
              group: nudge_config.nudge_group,
            ),
            analytics: analytics_props(category: NUDGE_CATEGORY_CONTROL, cta_action: CTA_ACTION_CONTROL),
          )
        end

        # Treatment (#458) — install-command picker with a copy CTA. When
        # `installationMethods` is present BannerNudgeCard renders the CommandPicker and
        # suppresses the big CTA button, so we omit `ctaTitle`/`ctaHref` and surface a
        # secondary "Read the docs" link via `footer` (dismiss-and-redirect, same as
        # control's CTA). Category ends `_nudge_0`; primary action is `copy`.
        sig { returns(T::Hash[Symbol, T.untyped]) }
        def treatment_react_props
          base_react_props.merge(
            installationMethods: INSTALL_METHODS,
            defaultInstallationMethod: "auto",
            footer: {
              text: "Read the docs",
              href: dismiss_and_redirect_path(
                destination_key: nudge_config.destination_key,
                business_id: business.id,
                notice: nudge_config.nudge_id,
                group: nudge_config.nudge_group,
              ),
            },
            analytics: analytics_props(category: NUDGE_CATEGORY_TREATMENT, cta_action: CTA_ACTION_TREATMENT),
          )
        end

        private

        # Props shared by both arms (title, icon, copy, dismissal, test selector).
        sig { returns(T::Hash[Symbol, T.untyped]) }
        def base_react_props
          {
            title: "#{business.safe_profile_name} has enabled Copilot CLI for you",
            # Render as a standalone dashboard card (own border/padding, <h3> title)
            # rather than the default settings-row style.
            displayStyle: "dashboard",
            segments: [
              { type: "text", content: "A coding agent in your terminal that plans multi-step issues, edits across files, runs tests, and opens PRs." },
            ],
            iconPath: image_path(ICON_PATH),
            dismissPath: enterprise_dismiss_notice_path(
              notice: nudge_config.nudge_id,
              business_id: business.id,
              group: nudge_config.nudge_group,
            ),
            testSelector: "enterprise-dashboard-#{business.id}-dfd-#{nudge_config.nudge_type}-nudge",
          }
        end

        sig { params(category: String, cta_action: String).returns(T::Hash[Symbol, T.untyped]) }
        def analytics_props(category:, cta_action:)
          {
            category: category,
            location: NUDGE_LOCATION,
            group: nudge_config.nudge_group,
            ctaAction: cta_action,
            entityId: business.id,
          }
        end

        sig { returns(Business) }
        attr_reader :business

        sig { returns(User) }
        attr_reader :user

        sig { returns(NudgeConfig) }
        memoize def nudge_config
          get_dashboard_nudge_config(NUDGE_KEY)
        end
      end
    end
  end
end
