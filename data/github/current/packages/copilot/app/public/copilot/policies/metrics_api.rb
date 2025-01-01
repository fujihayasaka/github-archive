# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class MetricsApi
      class << self
        include Copilot::Policy

        include Copilot::Policies::Concerns::Core
        include Copilot::Policies::Concerns::Mutable

        include Copilot::Policies::Concerns::Business::Propagatable
        include Copilot::Policies::Concerns::Instrumentable

        sig { override.returns(String) }
        def config_name
          "usage_telemetry_api"
        end

        sig { override.returns(String) }
        def display_name
          "Copilot Metrics API"
        end

        sig { override.returns(String) }
        def documentation_url
          "https://docs.github.com/en/rest/copilot/copilot-metrics?apiVersion=2022-11-28"
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def available_for?(entity)
          # not available for ghes/proxima
          return false if GitHub.multi_tenant_enterprise?

          # this policy is only used at the org level
          return false if entity.sorbet_class == ::User

          true
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def preview?(entity)
          false
        end

        # since the metrics api is only for orgs/biz, it will
        # always be disabled for users
        sig { override.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(T.nilable(String)) }
        def effective_value(user, all_policies = nil)
          "disabled"
        end

        sig { override.params(business: Copilot::Business, org: Copilot::Organization).returns(T::Boolean) }
        def propagate_business_updates?(business, org)
          true
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
