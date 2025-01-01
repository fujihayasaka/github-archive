# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class EnterpriseOrganizationInvitation < Platform::Objects::Base
      model_name "BusinessOrganizationInvitation"

      scopeless_tokens_as_minimum

      visibility :under_development

      description "An invitation for an organization to become a part of an enterprise."

      implements Platform::Interfaces::Node # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject


      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        # TODO write proper permissions before making this object public
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        # Let site admins view all invitations
        return true if permission.viewer.site_admin?

        Promise.all([object.async_invitee, object.async_business]).then do |org, business|
          # Let any organization admin see the invitation
          next true if org&.adminable_by?(permission.viewer)
          # Let any business admin see the invitation
          next true if business&.owner?(permission.viewer)
          nil
        end
      end

      global_id_field :id, description: "The Node ID of the EnterpriseOrganizationInvitation object" # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      created_at_field

      field :status, Enums::EnterpriseOrganizationInvitationStatus, method: :status, description: "The stage of the flow where this invitation is.", null: false

      # This can return `nil` if the API viewer doesn't have the proper scope to see it
      field :enterprise, Objects::Enterprise, method: :async_business, description: "The enterprise the invitation is for.", null: true

      field :invitee, Objects::Organization, method: :async_invitee, description: "The organization who was invited to become a part of the enterprise.", null: false

      field :inviter, Objects::User, method: :async_inviter, description: "The user who created the invitation.", null: false

      field :accepted_at, Platform::Scalars::DateTime, null: true, description: "The date and time when the invitation was accepted."

      field :confirmed_at, Platform::Scalars::DateTime, null: true, description: "The date and time when the invitation was confirmed."

      field :canceled_at, Platform::Scalars::DateTime, null: true, description: "The date and time when the invitation was canceled."

      field :completed_at, Platform::Scalars::DateTime, null: true, description: "The date and time when the invitation was marked as completed."

      def completed_at
        unless self.class.viewer_is_site_admin?(context[:viewer], self.class.name)
          raise Errors::Forbidden.new \
            "#{context[:viewer].display_login} does not have the right permission to retrieve completed_at"
        end
        @object.completed_at
      end

      field :completed_by, Objects::User, description: "The user who completed the invitation.", null: true

      def completed_by
        @object.async_completed_by.then do |completed_by|
          unless self.class.viewer_is_site_admin?(context[:viewer], self.class.name)
            raise Errors::Forbidden.new \
              "#{context[:viewer].display_login} does not have the right permission to retrieve completed_by"
          end
          completed_by
        end
      end

      field :needed_seat_count, Int, null: true, description: "The number of unique users in the invited organization that are not already members of the enterprise. Only visible once the invitation has been accepted."
      def needed_seat_count
        unless object.accepted?
          return nil
        end
        Promise.all([object.async_business, object.async_invitee]).then do |business, org|
          Promise.all([
            business.async_license_usage,
            object.business.async_organizations,
            business.async_customer,
            org.async_customer,
            org.async_business
          ]).then do
            object.async_invitee.then do
              object.needed_seat_count
            end
          end
        end
      end
    end
  end
end
