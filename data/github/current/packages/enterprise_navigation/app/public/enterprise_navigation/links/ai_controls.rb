# typed: strict
# frozen_string_literal: true

module EnterpriseNavigation
  module Links
    module AiControls
      extend T::Helpers
      include GitHub::Memoizer
      include UrlHelpers
      include EnterpriseNavigation::Links::SharedDependency

      sig { returns T::Array[EnterpriseNavigation::Group] }
      memoize def ai_controls_groups
        return [] unless @business && @business.actor_can_read_enterprise_ai_controls?(@user)
        [main_group]
      end

      sig { returns T::Array[EnterpriseNavigation::Link] }
      memoize def ai_controls_menu_items
        ai_controls_groups.flat_map(&:links)
      end

      sig { returns EnterpriseNavigation::Group }
      memoize def main_group
        EnterpriseNavigation::Group.new(
          type: EnterpriseNavigation::GroupType::DIVIDER,
          links: [
            agents_controls_menu_item,
            copilot_controls_menu_item,
            mcp_controls_menu_item
          ]
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def agents_controls_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Agents",
          link_path: Rails.application.routes.url_helpers.agents_enterprise_ai_controls_enterprise_path(@business),
          highlight: %i(
            businesses_ai_controls_agents
          ),
          icon: :agent
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def copilot_controls_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Copilot",
          link_path: Rails.application.routes.url_helpers.copilot_enterprise_ai_controls_enterprise_path(@business),
          highlight: %i(
            businesses_ai_controls_copilot
          ),
          icon: :copilot
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def mcp_controls_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "MCP",
          link_path: Rails.application.routes.url_helpers.mcp_enterprise_ai_controls_enterprise_path(@business),
          highlight: %i(
            businesses_ai_controls_mcp
          ),
          icon: :mcp
        )
      end
    end
  end
end
