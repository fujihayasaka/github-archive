# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class AgentMode
      class << self
        include Copilot::PolicyInterface

        include Copilot::Policies::Concerns::Core
        include Copilot::Policies::Concerns::Mutable

        include Copilot::Policies::Concerns::Business::Propagatable
        include Copilot::Policies::Concerns::Instrumentable
        include Copilot::Policies::Concerns::Twirpable

        include Copilot::Policies::Inheritance::BusinessPrecedence
        include Copilot::Policies::Inheritance::MostRestrictiveBusiness
        include Copilot::Policies::Inheritance::LeastRestrictiveOrg

        sig { override.returns(String) }
        def config_name
          "agent_mode"
        end

        # UI
        sig { override.returns(String) }
        def display_name
          "Copilot Agent Mode in IDE Chat"
        end

        sig { override.returns(String) }
        def documentation_url
          "https://docs.github.com/en/copilot/how-tos/chat-with-copilot/chat-in-ide?tool=visualstudio#using-agent-mode-1"
        end

        sig { override.params(business: Copilot::Business).returns(Copilot::Policies::PolicyDescription) }
        def business_setting_description(business)
          [
            "If enabled, organizations may use Agent Mode within their IDE to interact with Copilot for the purpose of reasoning through requests, planning tasks, and making changes to the codebase.",
            PolicyDescriptionChunk.new(text: "Learn more.", href: documentation_url)
          ]
        end

        sig { override.params(org: Copilot::Organization).returns(Copilot::Policies::PolicyDescription) }
        def organization_setting_description(org)
          [
            "If enabled, members of this organization may use Agent Mode within their IDE to interact with Copilot for the purpose of reasoning through requests, planning tasks, and making changes to the codebase.",
            PolicyDescriptionChunk.new(text: "Learn more about #{display_name}.", href: documentation_url)
          ]
        end

        sig { override.params(user: Copilot::User).returns(Copilot::Policies::PolicyDescription) }
        def user_setting_description(user)
          [
            "You can use",
            PolicyDescriptionChunk.new(text: display_name, href: documentation_url),
            "to interact with Copilot for the purpose of reasoning through requests, planning tasks, and making changes to the codebase.",
          ]
        end

        sig { override.params(copilot_business: Copilot::Business).returns(T::Boolean) }
        def viewable_by_business?(copilot_business)
          (copilot_business.feature_flag_enabled?(:copilot_agent_mode_show_policy, default: false) && super) || false
        end

        sig { override.params(copilot_org: Copilot::Organization).returns(T::Boolean) }
        def viewable_by_org?(copilot_org)
          copilot_org.feature_flag_enabled?(:copilot_agent_mode_show_policy, default: false) && super
        end

        sig { override.params(copilot_user: Copilot::User).returns(T::Boolean) }
        def editable_by_user?(copilot_user)
          false
        end

        sig { override.params(copilot_user: Copilot::User).returns(T::Boolean) }
        def viewable_by_user?(copilot_user)
          (copilot_user.feature_flag_enabled?(:copilot_agent_mode_show_policy, default: false) && !copilot_user.has_cfi_access? && super) || false
        end

        # END UI

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def available_for?(entity)
          true
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def preview?(entity)
          false
        end

        sig { override.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(String) }
        def effective_value(user, all_policies = nil)
          # feature flag overrides for quick ship
          return "disabled" if user.feature_flag_enabled?(:agent_mode_policy_disabled, default: false)
          return "enabled" if user.feature_flag_enabled?(:agent_mode_policy_enabled, default: false)

          return "enabled" if user.has_cfi_access?

          # if there is no inherited or fallback, the policy is unconfigured.
          # we will default to enabled in that case to provide non-disruptive experience.
          user_inherited_policy(user, all_policies) || "enabled"
        end

        sig { override.returns(Symbol) }
        def twirp_key
          :agent_mode
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
            enabled: :AGENT_MODE_ENABLED,
            disabled: :AGENT_MODE_DISABLED,
            no_policy: :AGENT_MODE_NO_POLICY,
            unconfigured: :AGENT_MODE_UNCONFIGURED,
            unknown: :AGENT_MODE_UNKNOWN
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
            enabled: MonolithTwirp::Copilot::Users::V1::AgentMode::AGENT_MODE_ENABLED,
            disabled: MonolithTwirp::Copilot::Users::V1::AgentMode::AGENT_MODE_DISABLED,
            no_policy: MonolithTwirp::Copilot::Users::V1::AgentMode::AGENT_MODE_ENABLED, # default to enabled
            unconfigured: MonolithTwirp::Copilot::Users::V1::AgentMode::AGENT_MODE_UNCONFIGURED,
            invalid: MonolithTwirp::Copilot::Users::V1::AgentMode::AGENT_MODE_INVALID
          }
        end
      end
    end
  end
end
