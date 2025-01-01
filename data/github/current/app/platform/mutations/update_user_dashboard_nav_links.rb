# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateUserDashboardNavLinks < Platform::Mutations::Base
      description "Update sort order and hidden status of the current user's dashboard navigation links."
      minimum_accepted_scopes ["user"]
      mobile_only true
      extras [:execution_errors]

      def self.async_api_can_modify?(permission, **inputs)
        permission.access_allowed?(
          :update_user,
          resource: permission.viewer,
          current_repo: nil,
          current_org: nil,
          allow_integrations: false,
          allow_user_via_granular_actor: false
        )
      end

      argument :sorted_links,
        type: [Enums::UserDashboardNavLinkIdentifier],
        description: "A set of UserDashboardNavLinkIdentifier enums in the sorted order.",
        required: true

      argument :hidden_links,
        type: [Enums::UserDashboardNavLinkIdentifier],
        description: "An optional list of UserDashboardNavLinkIdentifier enums to mark as hidden.",
        required: false

      field :dashboard, Objects::UserDashboard, "The saved links dashboard", null: true
      field :nav_links, [Objects::UserDashboardNavLink], "The saved links.", null: true
      error_fields

      def resolve(sorted_links:, hidden_links: [], execution_errors:)
        hidden_links.uniq.each do |hidden_link|
          unless sorted_links.include?(hidden_link)
            message = "Cannot hide links that are not in sorted links."
            Platform::UserErrors.append_legacy_mutation_error_messages_to_context(Array.wrap(message), execution_errors)

            return {
              nav_links: nil,
              errors: [{
                path: %w(input sortedLinks),
                message: message
              }]
            }
          end
        end

        dashboard = context[:viewer].dashboard || ::UserDashboard.create(user: context[:viewer])

        saved_links = dashboard.update_mobile_nav_links!(
          sorted_links: sorted_links,
          hidden_links: hidden_links
        )

        {
          dashboard: dashboard,
          nav_links: saved_links,
          errors: []
        }
      end
    end
  end
end
