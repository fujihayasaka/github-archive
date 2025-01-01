# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ExternalIdentityScimAttributes < Platform::Objects::Base
      description "SCIM attributes for the External Identity"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, scim_attributes)
        permission.typed_can_access?("ExternalIdentity", scim_attributes.identity)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.typed_can_see?("ExternalIdentity", object.identity)
      end

      minimum_accepted_scopes ["read:org", "read:enterprise"]

      field :username, String, description: "The userName of the SCIM identity", null: true

      def username
        @object.identity.async_identity_attribute_records.then do
          @object.identity.scim_user_data.user_name
        end
      end

      field :emails, [Platform::Objects::UserEmailMetadata], description: "The emails associated with the SCIM identity", null: true
      def emails
        @object.identity.async_identity_attribute_records.then do
          @object.identity.scim_user_data.emails_with_metadata
        end
      end

      field :groups, [String], description: "The groups linked to this identity in IDP", null: true

      def groups
        @object.identity.async_identity_attribute_records.then do
          @object.identity.scim_user_data.groups
        end
      end


      field :given_name, String, description: "Given name of the SCIM identity", null: true
      #   "givenName" : "Mona"
      def given_name
        @object.identity.async_identity_attribute_records.then do
          @object.identity.scim_user_data.given_name
        end
      end

      field :family_name, String, description: "Family name of the SCIM identity", null: true
      #   "familyName" : "Lisa"
      def family_name
        @object.identity.async_identity_attribute_records.then do
          @object.identity.scim_user_data.family_name
        end
      end


      field :external_id, String, description: "The externalId of the SCIM identity", null: true, visibility: :internal

      def external_id
        @object.identity.async_identity_attribute_records.then do
          @object.identity.scim_user_data.external_id
        end
      end
    end
  end
end
