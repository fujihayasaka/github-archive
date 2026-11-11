# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class McpRegistryConfigurationComponent < McpBaseComponent
      include GitHub::Memoizer

      DIALOG_ID = "mcp-registry-configure-dialog"

      sig { returns(String) }
      def dialog_id
        DIALOG_ID
      end

      sig { returns(T.nilable(Copilot::McpRegistry)) }
      memoize def registry
        copilot_business.mcp_registry
      end

      sig { returns(String) }
      def submit_path
        if registry.present?
          update_settings_copilot_mcp_registry_enterprise_path(@configurable.slug, registry&.id)
        else
          create_settings_copilot_mcp_registry_enterprise_path(@configurable.slug)
        end
      end

      sig { returns(Symbol) }
      def form_method
        registry.present? ? :put : :post
      end

      sig { returns(T.nilable(String)) }
      def registry_url
        registry&.registry_url
      end

      sig { returns(String) }
      def registry_type
        registry&.registry_type || "github"
      end

      sig { returns(String) }
      def registry_access
        copilot_business.mcp_registry_access
      end

      sig { returns(T::Boolean) }
      def configured?
        registry.present? && registry_url.present?
      end

      sig { returns(Copilot::McpRegistry) }
      def mcp_registry_model
        registry || Copilot::McpRegistry.new(entity: @configurable)
      end

      private

      sig { returns(Copilot::Business) }
      memoize def copilot_business
        Copilot::Business.new(@configurable)
      end
    end
  end
end
