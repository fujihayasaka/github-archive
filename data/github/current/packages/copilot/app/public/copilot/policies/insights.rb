# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class Insights
      API_URL = T.let("https://docs.github.com/en/enterprise-cloud@latest/rest/copilot/copilot-metrics?apiVersion=2022-11-28#get-copilot-enterprise-usage-metrics-for-a-specific-day".freeze, String)

      class << self
        include Copilot::Policy

        include Copilot::Policies::Concerns::Core
        include Copilot::Policies::Concerns::Business::Mutable
        include Copilot::Policies::Concerns::Organization::Mutable

        include Copilot::Policies::Concerns::Business::Propagatable
        include Copilot::Policies::Concerns::Instrumentable

        sig { override.returns(String) }
        def config_name
          "insights"
        end

        sig { override.returns(String) }
        def display_name
          "Copilot usage metrics"
        end

        sig { override.returns(String) }
        def documentation_url
          "https://docs.github.com/en/copilot/concepts/copilot-metrics"
        end

        sig { override.params(business: Copilot::Business).returns(Copilot::Policies::PolicyDescription) }
        def business_setting_description(business)
          if business.feature_flag_enabled?(:enterprise_copilot_metrics_fgp, default: false)
            [
              "If enabled, enterprise admins, billing managers, and authorized users can view Copilot usage metrics in a",
              PolicyDescriptionChunk.new(text: "dashboard", href: documentation_url),
              "and access the",
              PolicyDescriptionChunk.new(text: "Copilot Usage API", href: API_URL)
            ]
          else
            [
              "Enterprise administrators and billing managers can view expanded Copilot usage metrics in a",
              PolicyDescriptionChunk.new(text: "dashboard", href: documentation_url),
              "and access both enterprise-level and user-level data via an",
              PolicyDescriptionChunk.new(text: "API", href: API_URL)
            ]
          end
        end

        sig { override.params(org: Copilot::Organization).returns(Copilot::Policies::PolicyDescription) }
        def organization_setting_description(org)
          [
            "If enabled, organization admins and authorized users can access the Copilot Usage API.",
            PolicyDescriptionChunk.new(text: "Learn more about the Copilot Usage API.", href: documentation_url),
          ]
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def available_for?(entity)
          # TODO: this mt check is not present when displaying the policy for enterprises. is this correct?
          return false if GitHub.multi_tenant_enterprise?
          return false if entity.sorbet_class == ::User
          return false unless entity.feature_flag_enabled?(:copilot_insights_public_preview, default: false)

          true
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def preview?(entity)
          entity.feature_flag_enabled?(:copilot_insights_public_preview, default: false)
        end

        sig { override.returns(T::Boolean) }
        def dpa_covered?
          true
        end

        # won't need effective value for this one so we will just return "disabled" from this
        sig { override.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(String) }
        def effective_value(user, all_policies = nil)
          "disabled"
        end

        sig { override.returns(T::Boolean) }
        def skip_user_instrumentation?
          true
        end

        sig { override.returns(T::Boolean) }
        def hide_from_audit_log?
          true
        end

        private

        sig do override.returns({
            enabled: Symbol,
            disabled: Symbol,
            no_policy: Symbol,
            unconfigured: Symbol,
            unknown: Symbol
          })
        end
        def instrumentation_symbols
          {
            enabled: :INSIGHTS_ENABLED,
            disabled: :INSIGHTS_DISABLED,
            no_policy: :INSIGHTS_NO_POLICY,
            unconfigured: :INSIGHTS_UNCONFIGURED,
            unknown: :DESKTOP_UNKNOWN
          }
        end
      end
    end
  end
end
