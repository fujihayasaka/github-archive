# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateEnterpriseProfile < Platform::Mutations::Base
      description "Updates an enterprise's profile."

      minimum_accepted_scopes ["admin:enterprise"]

      argument :enterprise_id, ID, "The Enterprise ID to update.", required: true, loads: Objects::Enterprise
      argument :name, String, "The name of the enterprise.", required: false
      argument :description, String, "The description of the enterprise.", required: false
      argument :website_url, String, "The URL of the enterprise's website.", required: false
      argument :location, String, "The location of the enterprise.", required: false
      argument :security_contact_email, String, "The security contact email address of the enterprise.", required: false

      field :enterprise, Objects::Enterprise, "The updated enterprise.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, enterprise:, **inputs)
        permission.access_allowed?(:administer_business, resource: enterprise, repo: nil, organization: nil, allow_integrations: false, allow_user_via_granular_actor: false)
      end

      def resolve(enterprise:, **inputs)
        ensure_business_not_suspended!(enterprise)
        ensure_business_payment_completed!(enterprise)

        actor = context[:actor]
        viewer = context[:viewer]

        unless enterprise.owner?(actor)
          raise Errors::Forbidden.new("#{viewer.display_login} does not have permission to update this enterprise.")
        end

        # Attributes updated if necessary
        attributes = inputs.slice(:name, :description, :website_url, :location, :security_contact_email)

        if enterprise.update(attributes)
          { enterprise: enterprise }
        else
          raise Errors::Unprocessable.new(enterprise.errors.full_messages.join(", "))
        end
      end
    end
  end
end
