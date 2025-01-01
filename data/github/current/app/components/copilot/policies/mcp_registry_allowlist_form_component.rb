# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class McpRegistryAllowlistFormComponent < ApplicationComponent
      renders_one :description

      sig do params(
        display_name: String,
        configurable: (::Business),
        current_value: String,
        menu_items: T::Array[T.class_of(Copilot::Policies::MenuItems::McpRegistryAccess::Base)],
        ).void
      end
      def initialize(
          display_name:,
          configurable:,
          current_value:,
          menu_items: Copilot::Policies::Menus::MCP_ALLOWLIST
        )
        @display_name = display_name
        @configurable = configurable
        @copilot_business = T.let(copilot_object(configurable), (Copilot::Business))
        @current_value = current_value
        @menu_items = menu_items
      end

      sig { returns(T::Boolean) }
      def render?
        logged_in?
      end

      private

      sig { returns(T::Boolean) }
      def disabled
        !@copilot_business.mcp_enabled? || !@copilot_business.mcp_registry_url.present?
      end

      sig { returns(T::Array[Copilot::Policies::MenuItems::McpRegistryAccess::Base]) }
      def menu_items
        @menu_items.map do |item|
          item.new(copilot_configurable: copilot_object(@configurable))
        end.compact
      end

      sig { returns(String) }
      def submit_path
        if registry.present?
          update_settings_copilot_mcp_registry_enterprise_path(@configurable.slug, registry&.id)
        else
          create_settings_copilot_mcp_registry_enterprise_path(@configurable.slug)
        end
      end

      sig { returns(T.nilable(Copilot::McpAllowlist)) }
      def registry
        @copilot_business.mcp_registry
      end

      sig { returns(Symbol) }
      def path_method
        if registry.present?
          :put
        else
          :post
        end
      end

      sig { params(configurable_object: (::Business)).returns(Copilot::Business) }
      def copilot_object(configurable_object)
        Copilot::Business.new(configurable_object)
      end

      sig { returns(String) }
      def current_label
        menu_items.find { |item| item.checked? }&.text || "Allow all"
      end
    end
  end
end
