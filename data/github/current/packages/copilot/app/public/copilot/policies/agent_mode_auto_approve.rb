# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class AgentModeAutoApprove
      class << self
        include Copilot::Policy

        include Copilot::Policies::Concerns::Core
        include Copilot::Policies::Concerns::Business::Mutable
        include Copilot::Policies::Concerns::Organization::Mutable

        include Copilot::Policies::Concerns::Business::Propagatable
        include Copilot::Policies::Concerns::Instrumentable
        include Copilot::Policies::Concerns::Twirpable

        include Copilot::Policies::Inheritance::BusinessPrecedence
        include Copilot::Policies::Inheritance::MostRestrictiveBusiness
        include Copilot::Policies::Inheritance::LeastRestrictiveOrg

        sig { override.returns(String) }
        def config_name
          "agent_mode_auto_approve"
        end

        sig { override.returns(String) }
        def display_name
          "Auto-Approval in Copilot Agent Mode"
        end

        sig { override.returns(String) }
        def documentation_url
          ""
        end

        sig { override.params(business: Copilot::Business).returns(Copilot::Policies::PolicyDescription) }
        def business_setting_description(business)
          ["If enabled, users in the organization may use #{display_name} (currently supported by JetBrains plugin only)."]
        end

        sig { override.params(org: Copilot::Organization).returns(Copilot::Policies::PolicyDescription) }
        def organization_setting_description(org)
          ["If enabled, members of this organization may use #{display_name} (currently supported by JetBrains plugin only)."]
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def available_for?(entity)
          entity.feature_flag_enabled?(:copilot_agent_mode_auto_approve, default: false)
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def preview?(entity)
          false
        end

        sig { override.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(String) }
        def effective_value(user, all_policies = nil)
          return "disabled" if user.feature_flag_enabled?(:copilot_agent_mode_auto_approval_disabled, default: false)
          return "enabled" if user.has_cfi_access?
          return "enabled" unless user.copilot_businesses.any? { |b| available_for?(b) }

          # if there is no inherited or fallback, the policy is unconfigured.
          # we will default to enabled in that case to provide non-disruptive experience.
          user_inherited_policy(user, all_policies) || "enabled"
        end

        sig { override.returns(Symbol) }
        def twirp_key
          :auto_approve_agent_mode_setting
        end

        sig { override.returns(Symbol) }
        def instrumentation_key
          :auto_approve_agent_mode_setting
        end

        sig { override.params(copilot_org: Copilot::Organization).returns(T::Boolean) }
        def viewable_by_org?(copilot_org)
          copilot_org.feature_flag_enabled?(:copilot_agent_mode_auto_approve, default: false)
        end

        sig { override.params(business: Copilot::Business).returns(String) }
        def business_default_value(business)
          config_values[:enabled]
        end

        sig { override.params(org: Copilot::Organization).returns(String) }
        def org_default_value(org)
          config_values[:enabled]
        end

        sig { override.params(user: Copilot::User).returns(String) }
        def user_default_value(user)
          config_values[:enabled]
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
            enabled: :AUTO_APPROVE_AGENT_MODE_ENABLED,
            disabled: :AUTO_APPROVE_AGENT_MODE_DISABLED,
            no_policy: :AUTO_APPROVE_AGENT_MODE_NO_POLICY,
            unconfigured: :AUTO_APPROVE_AGENT_MODE_UNCONFIGURED,
            unknown: :AUTO_APPROVE_AGENT_MODE_UNKNOWN
          }
        end

        sig do override.returns({
            enabled: Integer,
            disabled: Integer,
            no_policy: Integer,
            unconfigured: Integer,
            invalid: Integer
          })
        end
        def twirp_values
          {
            enabled: MonolithTwirp::Copilot::Users::V1::AutoApproveAgentMode::AUTO_APPROVE_AGENT_MODE_ENABLED,
            disabled: MonolithTwirp::Copilot::Users::V1::AutoApproveAgentMode::AUTO_APPROVE_AGENT_MODE_DISABLED,
            no_policy: MonolithTwirp::Copilot::Users::V1::AutoApproveAgentMode::AUTO_APPROVE_AGENT_MODE_ENABLED,
            unconfigured: MonolithTwirp::Copilot::Users::V1::AutoApproveAgentMode::AUTO_APPROVE_AGENT_MODE_UNCONFIGURED,
            invalid: MonolithTwirp::Copilot::Users::V1::AutoApproveAgentMode::AUTO_APPROVE_AGENT_MODE_INVALID
          }
        end
      end
    end
  end
end
