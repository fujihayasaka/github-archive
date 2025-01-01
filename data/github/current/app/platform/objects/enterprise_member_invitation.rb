# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class EnterpriseMemberInvitation < Platform::Objects::Base
      model_name "BusinessAdministratorInvitation"

      scopeless_tokens_as_minimum

      description "An invitation for a user to become an unaffiliated member of an enterprise."

      implements_node templates: [[:eemi, :enterprise_id, :enterprise_member_invitation_id]], as: "EMI", ready_date: "2021-06-18" do |invitation|
        invitation.async_business.then do |business|
          {
            prefix: :eemi,
            enterprise_id: business.id,
            enterprise_member_invitation_id: invitation.id,
          }
        end
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        object.async_business.then do |business|
          business.async_customer.then do
            next false unless business.supports_unaffiliated_user_accounts?

            permission.access_allowed?(:view_business_administrator_invitation, resource: object,
              organization: nil, repo: nil,
              allow_integrations: true, allow_user_via_granular_actor: true)
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        # Let site admins view all invitations
        return true if permission.viewer&.site_admin?
        object.async_business.then { object.readable_by?(permission.viewer) }
      end

      created_at_field

      field :enterprise, Objects::Enterprise, description: "The enterprise the invitation is for.", null: false

      def enterprise
        object.async_business.then do |business|
          if object.email.present?
            # If the invitation was given via email + token,
            # use Models::Enterprise to give broader access to business data
            Models::Enterprise.new(business, object.hashed_token)
          else
            business
          end
        end
      end

      field :inviter, Objects::User, method: :async_inviter, description: "The user who created the invitation.", null: true

      field :invitee, Objects::User, method: :async_invitee, description: "The user who was invited to the enterprise.", null: true

      field :email, String, description: "The email of the person who was invited to the enterprise.", null: true
    end
  end
end
