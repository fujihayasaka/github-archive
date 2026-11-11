# typed: strict
# frozen_string_literal: true

module InProductTargeting
  module Components
    module DashboardNudges
      class CopilotCliForDevsNudgeComponent < ApplicationComponent
        include ApplicationComponent::Rescuable
        include InProductTargeting::NudgeConcern

        rescue_from StandardError, with: :nothing

        NUDGE_ID = T.let(:accelerate_ipm_copilot_cli_dashboard_for_devs, Symbol)
        NUDGE_CATEGORY = T.let("accelerate_ipm_copilot_cli_dashboard_for_devs", String)
        NUDGE_GROUP = T.let(:engage, Symbol)
        NUDGE_LOCATION = T.let("dashboard", String)
        FEATURE_FLAG = T.let(:accelerate_ipm_copilot_cli_dashboard_for_devs, Symbol)
        PARTIAL_NAME = T.let("banner-nudge-card", String)
        DESTINATION_KEY = T.let("accelerate_ipm_copilot_cli_dashboard_for_devs", String)
        ICON_PATH = T.let("modules/dashboard/promos/general/copilot-menu-no-indicator-1746823169.svg", String)

        COPILOT_CLI_USAGE_COHORT = T.let("2026_05_copilot_cli_usage_past_60d", String)
        COPILOT_CLI_USAGE_SNAPSHOT_DAY = T.let("2026-06-04", String)
        InstallMethod = T.type_alias { T::Hash[Symbol, String] }

        # `os` tags let CommandPicker auto-select the right method when
        # `defaultInstallationMethod: "auto"` is passed. npm has no `os` because
        # it runs everywhere; the OS-tagged options are preferred over it.
        INSTALL_METHODS = T.let(
          [
            { key: "homebrew", label: "Install with Homebrew", command: "brew install copilot-cli", os: "macos" },
            { key: "npm", label: "Install with npm", command: "npm install -g @github/copilot" },
            { key: "winget", label: "Install with WinGet", command: "winget install GitHub.Copilot", os: "windows" },
            { key: "curl", label: "Install with curl", command: "curl -fsSL https://gh.io/copilot-install | bash", os: "linux" },
          ].freeze,
          T::Array[InstallMethod]
        )

        sig { returns(User) }
        attr_reader :user

        sig do
          params(
            user: User,
            system_arguments: Primer::SystemArgumentsValue
          ).void
        end
        def initialize(user:, **system_arguments)
          @user = user
        end

        sig { returns(T.nilable(String)) }
        def call
          return nil unless render?

          user.track_nudge_impression(id: NUDGE_ID, group: NUDGE_GROUP)

          content_tag(:div, class: "tmp-mb-4") do
            render_react_partial(name: PARTIAL_NAME, props: banner_props)
          end
        end

        sig { returns(T::Boolean) }
        def render?
          return false unless user.feature_flag_enabled?(FEATURE_FLAG, default: false)
          return false unless user.subscribed_to_in_product_messages?
          return false if GitHub.multi_tenant_enterprise? || GitHub.enterprise?
          return false if user.is_enterprise_managed?
          return false if user.dismissed_notice?(NUDGE_ID.to_s)
          return false unless copilot_pro_or_pro_plus?(user)
          return false if used_copilot_cli_in_past_60d?(user)
          return false if user.businesses.any? { |business| is_business_in_active_dfd_trial?(business) }
          return false unless messaging_subscriptions_enabled?

          true
        end

        sig { returns(T::Array[InstallMethod]) }
        def install_methods
          INSTALL_METHODS
        end

        sig { returns(String) }
        def dismiss_path
          "/track-nudge-dismissal?id=#{NUDGE_ID}&group=#{NUDGE_GROUP}"
        end

        sig { returns(String) }
        def footer_href
          dismiss_and_redirect_path(
            destination_key: DESTINATION_KEY,
            notice: NUDGE_ID,
            group: NUDGE_GROUP,
            dismiss_scope: "user",
          )
        end

        # Public so the test can assert the prop shape without going through
        # render_inline (component tests don't implement `document_root_element`
        # which css_select needs). Mirrors `react_props` on the sibling enabled-CLI
        # dashboard nudge component.
        sig { returns(T::Hash[Symbol, T.untyped]) }
        def banner_props
          {
            title: "Get started with Copilot CLI",
            displayStyle: "dashboard",
            segments: [
              {
                type: "text",
                content: "A coding agent in your terminal that plans multi-step issues, edits across files, runs tests, and opens PRs.",
              },
            ],
            iconPath: image_path(ICON_PATH),
            dismissPath: dismiss_path,
            installationMethods: install_methods,
            defaultInstallationMethod: "auto",
            footer: {
              text: "Read the docs",
              href: footer_href,
            },
            analytics: {
              ctaAction: "copy",
              group: NUDGE_GROUP,
              location: NUDGE_LOCATION,
              category: NUDGE_CATEGORY,
              entityId: user.id,
            },
            testSelector: "dashboard-user-#{user.id}-#{NUDGE_ID}-nudge",
          }
        end

        private

        sig { params(current_user: User).returns(T::Boolean) }
        def copilot_pro_or_pro_plus?(current_user)
          copilot_user = Copilot::User.new(current_user)
          copilot_user.has_pro_access? || copilot_user.has_pro_plus_access?
        end

        sig { params(current_user: User).returns(T::Boolean) }
        def used_copilot_cli_in_past_60d?(current_user)
          !::InProductTargeting.domain.match?(
            user_id: current_user.id,
            cohort: COPILOT_CLI_USAGE_COHORT,
            day: COPILOT_CLI_USAGE_SNAPSHOT_DAY,
          ).nil?
        end

        sig { returns(T::Boolean) }
        def messaging_subscriptions_enabled?
          orgs_subscribed = user.organizations.all? do |organization|
            ::InProductTargeting.domain.messaging_subscribed?(field: "promotion_subscribed", organization_id: organization.id)
          end
          return false unless orgs_subscribed

          user.businesses.all? do |business|
            next false if business.trial_expired?

            ::InProductTargeting.domain.messaging_subscribed?(field: "promotion_subscribed", business_id: business.id)
          end
        end
      end
    end
  end
end
