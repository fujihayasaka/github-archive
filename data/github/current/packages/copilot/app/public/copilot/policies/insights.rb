# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class Insights
      class << self
        include Copilot::Policy

        include Copilot::Policies::Concerns::Core
        include Copilot::Policies::Concerns::Mutable

        include Copilot::Policies::Concerns::Business::Propagatable
        include Copilot::Policies::Concerns::Instrumentable

        sig { override.returns(String) }
        def config_name
          "insights"
        end

        sig { override.returns(String) }
        def display_name
          "Copilot Insights"
        end

        sig { override.returns(String) }
        def documentation_url
          "https://docs.github.com/en/enterprise-cloud@latest/early-access/copilot/dashboard"
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def available_for?(entity)
          return false if GitHub.multi_tenant_enterprise?
          return false unless entity.feature_flag_enabled?(:copilot_insights, default: false)
          return false if entity.sorbet_class == ::User

          true
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def preview?(entity)
          !entity.feature_flag_enabled?(:copilot_desktop_no_preview_badge, default: false)
        end

        # won't need effective value for this one so we will just return nil from this
        sig { override.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(T.nilable(String)) }
        def effective_value(user, all_policies = nil)
          nil
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
