# typed: strict
# frozen_string_literal: true

module InProductTargeting
  module Components
    module DashboardNudges
      # Renders the "{organization} has enabled Copilot CLI for you" organization
      # dashboard nudge as a React partial (BannerNudgeCard), migrated out of the
      # ERB OrganizationNudgeComponent variant `:ipm_accelerate_dashboard_copilot_cli_enabled`.
      #
      # Eligibility is UNCHANGED: it reuses OrganizationNudgeConcern's
      # `show_organization_dashboard_nudge?`, so the same users see the nudge as before.
      # Only the presentation moves from ERB to React. Mirrors the enterprise
      # CopilotCliEnabledDashboardNudgeComponent (Business path).
      class OrganizationCopilotCliEnabledDashboardNudgeComponent < ApplicationComponent
        include ApplicationComponent::Rescuable
        include InProductTargeting::OrganizationNudgeConcern

        rescue_from StandardError, with: :nothing

        NudgeConfig = InProductTargeting::NudgeConcern::NudgeConfig

        NUDGE_KEY = T.let(:dashboard_copilot_cli_enabled, Symbol)
        # Distinct hydro categories per A|B arm so impressions/clicks/dismissals can be
        # compared in analytics. Control keeps the existing `_nudge_1`; treatment is `_nudge_0`.
        NUDGE_CATEGORY_CONTROL = T.let("ipm_accelerate_dashboard_copilot_cli_enabled_nudge_1", String)
        NUDGE_CATEGORY_TREATMENT = T.let("ipm_accelerate_dashboard_copilot_cli_enabled_nudge_0", String)
        NUDGE_LOCATION = T.let("dashboard", String)
        CTA_ACTION_CONTROL = T.let("get_started_with_copilot_cli", String)
        CTA_ACTION_TREATMENT = T.let("copy", String)
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

        sig { params(organization: Organization, user: User).void }
        def initialize(organization:, user:)
          @organization = T.let(organization, Organization)
          @user = T.let(user, User)
        end

        sig { returns(T.nilable(String)) }
        def call
          return unless render?

          InProductTargeting::NudgeMemory.new(user).save_a_copy_of_impression_analytics_to_dotcom(id: nudge_config.nudge_id, group: nudge_config.nudge_group, org_id: organization.id)

          content_tag(:div, class: "tmp-mb-4") do
            render_react_partial(name: PARTIAL_NAME, props: react_props)
          end
        end

        sig { returns(T::Boolean) }
        def render?
          return false unless user.subscribed_to_in_product_messages?
          return false unless ::InProductTargeting.domain.messaging_subscribed?(field: "promotion_subscribed", organization_id: organization.id)
          business = organization.business
          return false if business && !::InProductTargeting.domain.messaging_subscribed?(field: "promotion_subscribed", business_id: business.id)

          show_organization_dashboard_nudge?(user, organization, NUDGE_KEY)
        end

        # A|B test (issue #502): the backend owns which variant renders. The shared
        # nudge concern decides 0 (treatment) vs 1 (control); this component builds the
        # matching props AND hydro category together, so analytics and UI can never
        # drift. The React component is unaware an experiment exists — treatment is purely
        # additive props. Mirrors the enterprise CopilotCliEnabledDashboardNudgeComponent.
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
            ctaHref: dismiss_and_redirect_path(
              destination_key: nudge_config.destination_key,
              organization_id: organization.id,
              notice: nudge_config.nudge_id,
              group: nudge_config.nudge_group,
            ),
            analytics: analytics_props(category: NUDGE_CATEGORY_CONTROL, cta_action: CTA_ACTION_CONTROL),
          )
        end

        # Treatment — install-command picker with a copy CTA. When `installationMethods`
        # is present BannerNudgeCard renders the CommandPicker and suppresses the big CTA
        # button, so we omit `ctaTitle`/`ctaHref` and surface a secondary "Read the docs"
        # link via `footer` (dismiss-and-redirect, same as control's CTA). Category ends
        # `_nudge_0`; primary action is `copy`.
        sig { returns(T::Hash[Symbol, T.untyped]) }
        def treatment_react_props
          base_react_props.merge(
            installationMethods: INSTALL_METHODS,
            defaultInstallationMethod: "auto",
            footer: {
              text: "Read the docs",
              href: dismiss_and_redirect_path(
                destination_key: nudge_config.destination_key,
                organization_id: organization.id,
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
            title: "#{organization.safe_profile_name} has enabled Copilot CLI for you",
            displayStyle: "dashboard",
            segments: [
              { type: "text", content: "A coding agent in your terminal that plans multi-step issues, edits across files, runs tests, and opens PRs." },
            ],
            iconPath: image_path(ICON_PATH),
            dismissPath: organization_dismiss_notice_path(
              notice: nudge_config.nudge_id,
              organization_id: organization.id,
              group: nudge_config.nudge_group,
            ),
            testSelector: "dashboard-organization-#{organization.id}-#{nudge_config.nudge_type}-nudge",
          }
        end

        sig { params(category: String, cta_action: String).returns(T::Hash[Symbol, T.untyped]) }
        def analytics_props(category:, cta_action:)
          {
            category: category,
            location: NUDGE_LOCATION,
            group: nudge_config.nudge_group,
            ctaAction: cta_action,
            entityId: organization.id,
          }
        end

        sig { returns(Organization) }
        attr_reader :organization

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
