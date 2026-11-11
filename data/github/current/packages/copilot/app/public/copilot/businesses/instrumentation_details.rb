# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Copilot
  module Businesses
    module InstrumentationDetails
      extend T::Helpers
      include Copilot::Businesses::Signatures
      include Copilot::Instrumentation::ModelDetails

      abstract!

      sig { override.returns(Symbol) }
      def copilot_enabled_setting
        return :COPILOT_ALL_ORGANIZATIONS if copilot_enabled_for_all_organizations?
        return :COPILOT_DISABLED if copilot_disabled?
        return :COPILOT_SELECTED_ORGANIZATIONS if copilot_enabled_for_selected_organizations?
        return :COPILOT_UNCONFIGURED if copilot_unconfigured?

        :COPILOT_UNKNOWN
      end

      sig { override.returns(Symbol) }
      def copilot_overages_setting
        return :OVERAGES_UNCONFIGURED unless overages_configured?
        return :OVERAGES_ENABLED if overages_enabled?
        return :OVERAGES_DISABLED if overages_disabled?
        return :OVERAGES_NO_POLICY if overages_no_policy?

        :OVERAGES_UNKNOWN
      end

      sig { returns(Symbol) }
      def copilot_mcp_registry_access
        return :MCP_REGISTRY_ACCESS_ALLOW_ALL if mcp_registry_access_is?("allow_all")
        return :MCP_REGISTRY_ACCESS_REGISTRY_ONLY if mcp_registry_access_is?("registry_only")

        :MCP_REGISTRY_ACCESS_UNKNOWN
      end

      sig { returns(Symbol) }
      def copilot_mcp_registry_type
        registry = mcp_registry
        return :MCP_REGISTRY_TYPE_EXTERNAL if registry&.registry_type_external?
        return :MCP_REGISTRY_TYPE_GITHUB if registry&.registry_type_github?

        :MCP_REGISTRY_TYPE_UNKNOWN
      end

      sig { returns(T::Hash[Symbol, T.nilable(T.any(Symbol, String))]) }
      def copilot_mcp_registry_setting
        {
          mcp_registry_url: mcp_registry_url,
          mcp_registry_access: copilot_mcp_registry_access,
          mcp_registry_type: copilot_mcp_registry_type
        }
      end

      sig { returns(Symbol) }
      def copilot_coding_agent_enterprise_management_setting
        return :CODING_AGENT_ENTERPRISE_MANAGEMENT_ENABLED if coding_agent_enterprise_management_enabled?
        return :CODING_AGENT_ENTERPRISE_MANAGEMENT_DISABLED if coding_agent_enterprise_management_disabled?

        :CODING_AGENT_ENTERPRISE_MANAGEMENT_UNCONFIGURED
      end

      sig { override.returns(T::Hash[Symbol, Symbol]) }
      def copilot_business_settings
        # get the settings hash and merge in some special cases for policies
        # that don't use the new system
        Copilot::Policies.instrumentation_hash(T.bind(self, Copilot::Business)).merge({
          copilot_enabled_setting: copilot_enabled_setting,
          overages_setting: copilot_overages_setting,
          mcp_registry_setting: copilot_mcp_registry_setting,
          coding_agent_enterprise_management_setting: copilot_coding_agent_enterprise_management_setting,
        })
      end
      alias_method :copilot_settings, :copilot_business_settings

      sig { params(actor: ::User, old_settings: T::Hash[Symbol, Symbol], new_settings: T::Hash[Symbol, Symbol]).void }
      def instrument_settings_changed(actor, old_settings, new_settings)
        Copilot::Instrumenter.instrument_enterprise_settings_changed(
          actor,
          business_object,
          old_settings:,
          new_settings:,
        )
      end
    end
  end
end
