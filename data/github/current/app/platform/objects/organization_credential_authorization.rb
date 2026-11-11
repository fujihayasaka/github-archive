# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class OrganizationCredentialAuthorization < Platform::Objects::Base
      model_name "Organization::CredentialAuthorization"
      description "A CredentialAuthorization between an Organization and a User."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, org_domain)
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      scopeless_tokens_as_minimum

      visibility :under_development

      global_id_field :id, description: "The Node ID of the OrganizationCredentialAuthorization object" # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      implements Platform::Interfaces::Node # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      database_id_field

      field :credential, Unions::AuthorizedCredential, description: "The PublicKey or OauthAccess credential linked to this OrganizationCredentialAuthorization", null: true

      def credential
        @object.async_credential.then do
          @object.credential
        end
      end

      field :credential_type, Enums::OrganizationCredentialAuthorizationCredential, description: "The credential type that this OrganizationCredentialAuthorization authorizes.", null: false

      def credential_type
        if @object.using_personal_access_token?
          T.must(Enums::OrganizationCredentialAuthorizationCredential.values["PERSONAL_ACCESS_TOKEN"]).value
        else
          T.must(Enums::OrganizationCredentialAuthorizationCredential.values["PUBLIC_KEY"]).value
        end
      end
    end
  end
end
