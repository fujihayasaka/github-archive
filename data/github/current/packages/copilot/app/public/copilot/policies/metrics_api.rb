# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class MetricsApi
      class << self
        include Copilot::PolicyInterface

        include Copilot::Policies::Concerns::Core
        include Copilot::Policies::Concerns::Business::Mutable
        include Copilot::Policies::Concerns::Organization::Mutable

        include Copilot::Policies::Concerns::Business::Propagatable
        include Copilot::Policies::Concerns::Instrumentable

        sig { override.returns(String) }
        def config_name
          "usage_telemetry_api"
        end

        sig { override.returns(String) }
        def display_name
          "Copilot metrics API"
        end

        sig { override.returns(String) }
        def documentation_url
          "https://docs.github.com/en/rest/copilot/copilot-metrics?apiVersion=2022-11-28"
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def available_for?(entity)
          # this policy is only used at the org level
          return false if entity.sorbet_class == ::User

          # not available for ghes/proxima
          return false if GitHub.multi_tenant_enterprise?

          true
        end

        sig { override.params(business: Copilot::Business).returns(Copilot::Policies::PolicyDescription) }
        def business_setting_description(business)
          [
            "If enabled, enterprise and organization administrators can query the",
            PolicyDescriptionChunk.new(text: display_name, href: documentation_url),
            "for insights into Copilot usage."
          ]
        end

        sig { override.params(org: Copilot::Organization).returns(Copilot::Policies::PolicyDescription) }
        def organization_setting_description(org)
          [
            "If enabled, organization administrators can query the #{display_name} for insights into Copilot usage.",
            PolicyDescriptionChunk.new(text: "Learn more about the #{display_name}.", href: documentation_url)
          ]
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def preview?(entity)
          false
        end

        # since the metrics api is only for orgs/biz, it will
        # always be disabled for users
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

        sig { override.params(copilot_business: Copilot::Business).returns(String) }
        def business_default_value(copilot_business)
          config_values[:disabled]
        end

        sig { override.params(copilot_org: Copilot::Organization).returns(String) }
        def org_default_value(copilot_org)
          config_values[:disabled]
        end

        sig { override.params(copilot_user: Copilot::User).returns(String) }
        def user_default_value(copilot_user)
          config_values[:disabled]
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
            enabled: :USAGE_TELEMETRY_API_ENABLED,
            disabled: :USAGE_TELEMETRY_API_DISABLED,
            no_policy: :USAGE_TELEMETRY_API_NO_POLICY,
            unconfigured: :USAGE_TELEMETRY_API_DISABLED,
            unknown: :USAGE_TELEMETRY_API_UNKNOWN
          }
        end
      end
    end
  end
end
