# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class Mcp
      class << self
        include Copilot::Policy

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
          "mcp"
        end

        sig { override.returns(String) }
        def display_name
          "MCP servers in Copilot"
        end

        # there are a few docs urls, come back to this later perhaps
        sig { override.returns(String) }
        def documentation_url
          ""
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def available_for?(entity)
          return false if GitHub.single_business_environment?

          true
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def preview?(entity)
          false
        end

        sig { override.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(T.nilable(String)) }
        def effective_value(user, all_policies = nil)
          return "disabled" unless available_for?(user)
          return "enabled" if user.has_cfi_access?

          # inherited value from org or business
          inherited_policy = user_inherited_policy(user, all_policies)

          # the inherited value will be one of enabled or disabled (or nil)
          if !inherited_policy.nil?
            inherited_policy
          else
            # if the inherited value is nil, first try and do the ea fallback.
            # if there is no fallback, the policy is unconfigured
            user.business_copilot_provider_ea_user_fallback_policy(:mcp) || "unconfigured"
          end
        end

        sig { override.params(business: Copilot::Business, org: Copilot::Organization).returns(T::Boolean) }
        def propagate_business_updates?(business, org)
          true
        end

        sig { override.returns(Symbol) }
        def twirp_key
          :mcp
        end

        sig { override.params(copilot_org: Copilot::Organization).returns(T::Boolean) }
        def viewable_by_org?(copilot_org)
          !GitHub.multi_tenant_enterprise? || copilot_org.feature_flag_enabled?(:coding_agent_in_proxima, default: false)
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
            enabled: :MCP_ENABLED,
            disabled: :MCP_DISABLED,
            no_policy: :MCP_NO_POLICY,
            unconfigured: :MCP_UNCONFIGURED,
            unknown: :MCP_UNKNOWN
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
            enabled: MonolithTwirp::Copilot::Users::V1::MCP::MCP_ENABLED,
            disabled: MonolithTwirp::Copilot::Users::V1::MCP::MCP_DISABLED,
            no_policy: MonolithTwirp::Copilot::Users::V1::MCP::MCP_DISABLED,
            unconfigured: MonolithTwirp::Copilot::Users::V1::MCP::MCP_UNCONFIGURED,
            invalid: MonolithTwirp::Copilot::Users::V1::MCP::MCP_INVALID
          }
        end
      end
    end
  end
end
