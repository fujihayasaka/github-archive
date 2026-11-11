# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class Mcp
      MCP_CHAT_DOCS = "https://docs.github.com/en/copilot/customizing-copilot/extending-copilot-chat-with-mcp"
      MCP_CODING_AGENT_DOCS = "https://docs.github.com/en/copilot/customizing-copilot/extending-copilot-coding-agent-with-mcp"

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

        sig { override.params(business: Copilot::Business).returns(Copilot::Policies::PolicyDescription) }
        def business_setting_description(business)
          [
            "Users can configure Model Context Protocol (MCP) servers for Copilot in all Copilot editors and Coding Agent. See MCP docs for",
            PolicyDescriptionChunk.new(text: "Copilot Chat", href: MCP_CHAT_DOCS),
            "and",
            PolicyDescriptionChunk.new(text: "Coding Agent", href: MCP_CODING_AGENT_DOCS)
          ]
        end

        sig { override.params(org: Copilot::Organization).returns(Copilot::Policies::PolicyDescription) }
        def organization_setting_description(org)
          [
            "If enabled, users can configure Model Context Protocol (MCP) servers (including third-party servers) for Copilot in all Copilot editors and Coding Agent. See MCP docs for",
            PolicyDescriptionChunk.new(text: "Copilot Chat", href: MCP_CHAT_DOCS),
            "and",
            PolicyDescriptionChunk.new(text: "Coding Agent", href: MCP_CODING_AGENT_DOCS)
          ]
        end

        sig { override.params(user: Copilot::User).returns(Copilot::Policies::PolicyDescription) }
        def user_setting_description(user)
          mcp_platforms = user.has_copilot_standalone_business? ? "all Copilot editors." : "all Copilot editors and Coding Agent."

          ["Connect MCP servers to Copilot in #{mcp_platforms}"]
        end

        sig { override.params(copilot_user: Copilot::User).returns(T::Boolean) }
        def viewable_by_user?(copilot_user)
          return false if GitHub.multi_tenant_enterprise? || copilot_user.has_limited_access?

          true
        end

        sig { override.params(copilot_user: Copilot::User).returns(T::Boolean) }
        def editable_by_user?(copilot_user)
          return false unless viewable_by_user?(copilot_user)

          true
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def available_for?(entity)
          # this also is not checked for enterprises
          # from what i can see we also dont verify single biz to display mcp tab either
          return false if GitHub.single_business_environment?

          true
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def preview?(entity)
          false
        end

        sig { override.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(String) }
        def effective_value(user, all_policies = nil)
          return "disabled" unless available_for?(user)
          return "enabled" if user.has_cfi_access?

          # inherited value from org or business
          user_inherited_policy(user, all_policies) || "unconfigured"
        end

        sig { override.returns(Symbol) }
        def twirp_key
          :mcp
        end

        sig { override.params(copilot_org: Copilot::Organization).returns(T::Boolean) }
        def viewable_by_org?(copilot_org)
          !GitHub.multi_tenant_enterprise? || copilot_org.feature_flag_enabled?(:coding_agent_in_proxima, default: false)
        end

        sig { override.params(user: Copilot::User).returns(String) }
        def user_default_value(user)
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
