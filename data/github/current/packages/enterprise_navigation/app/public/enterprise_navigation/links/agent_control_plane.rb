# typed: strict
# frozen_string_literal: true

module EnterpriseNavigation
  module Links
    module AgentControlPlane
      extend T::Helpers
      include GitHub::Memoizer
      include UrlHelpers
      include EnterpriseNavigation::Links::SharedDependency

      sig { returns T::Array[EnterpriseNavigation::Group] }
      memoize def agent_control_plane_groups
        [main_group]
      end

      sig { returns T::Array[EnterpriseNavigation::Link] }
      memoize def agent_control_plane_menu_items
        agent_control_plane_groups.flat_map(&:flat_links)
      end

      sig { returns EnterpriseNavigation::Group }
      memoize def main_group
        EnterpriseNavigation::Group.new(
          type: EnterpriseNavigation::GroupType::DIVIDER,
          links: [
            agents_menu_item,
          ]
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def agents_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Agents",
          link_path: Rails.application.routes.url_helpers.agents_enterprise_copilot_enterprise_path(@business),
          highlight: %i(
            businesses_copilot_agents
          ),
          icon: :agent
        )
      end

    end
  end
end
