# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class UserEmail < Platform::Objects::Base
      description "An user email record."

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

      implements Platform::Interfaces::Node # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      global_id_field :id, description: "The Node ID of the UserEmail object" # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      created_at_field null: true

      field :email, String, description: "The email address.", null: false

      field :deobfuscated_email, String, description: "The email address.", null: false

      field :is_verified, Boolean, description: "Is the email address verified?", null: false, method: :verified?

      field :user, Objects::User, description: "User this email belongs to.", method: :async_user, null: false

      field :email_domain_reputation, Objects::SpamuraiReputation, description: "Email domain reputation.", null: false

      def email_domain_reputation
        EmailDomainReputationRecord.reputation(@object.email)
      end

      field :email_domain_metadata, Objects::EmailDomainMetadata, description: "Email domain metadata.", null: false

      def email_domain_metadata
        EmailDomainReputationRecord.metadata(@object.email)
      end
    end
  end
end
