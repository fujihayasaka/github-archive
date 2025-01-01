# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class OrganizationStafftoolsInfo < Platform::Objects::Base
      description "Organization information only visible to site admin"

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
        Platform::Objects::Base::SiteAdminCheck.viewer_is_site_admin?(permission.viewer, self.class.name)
      end

      visibility :internal

      minimum_accepted_scopes ["site_admin"]

      implements Interfaces::AccountStafftoolsInfo

      field :invitation_metadata, Objects::OrganizationInvitationMetadata, description: "Information about organization invitations.", null: false

      def invitation_metadata
        Loaders::OrganizationInvitationMetadata.load(@object.account.id)
      end

      field :associated_record_creation_velocity, Integer, description: "Records created per hour while active.", null: false do
        argument :type, Enums::OrganizationAssociatedRecordType, "The associated record type", required: true
      end

      def associated_record_creation_velocity(**arguments)
        Loaders::AssociatedRecordCreationVelocity.load(@object.account, arguments[:type])
      end

      field :associated_record_first_created_at, Scalars::DateTime, description: "First created at time for record type.", null: true do
        argument :type, Enums::OrganizationAssociatedRecordType, "The associated record type", required: true
      end

      def associated_record_first_created_at(**arguments)
        Loaders::AssociatedRecordFirstCreatedAt.load(@object.account, arguments[:type])
      end

      field :billing_email, String, description: "The organization billing email address.", null: true

      def billing_email
        @object.account.billing_email
      end

      field :billing_email_domain_reputation, Objects::SpamuraiReputation, description: "Billing email domain reputation.", null: false

      def billing_email_domain_reputation
        EmailDomainReputationRecord.reputation(@object.account.billing_email)
      end

      field :billing_email_domain_metadata, Objects::EmailDomainMetadata, description: "Billing email domain metadata.", null: false

      def billing_email_domain_metadata
        EmailDomainReputationRecord.metadata(@object.account.billing_email)
      end

      field :interaction_ability, Objects::RepositoryInteractionAbility, "The interaction ability settings for this organization.", null: false

      def interaction_ability
        Platform::Models::RepositoryInteractionAbility.new(@object.account)
      end

      field :enterprise, Objects::Enterprise, description: "The enterprise this organization belongs to.", null: true

      def enterprise
        @object.account.async_business
      end

      field :members, Connections::OrganizationStafftoolsMember, description: "The list of organization members", null: true

      def members
        @object.account.people
      end
    end
  end
end
