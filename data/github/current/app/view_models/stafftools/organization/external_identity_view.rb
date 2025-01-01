# typed: true
# frozen_string_literal: true

module Stafftools
  module Organization
    class ExternalIdentityView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      attr_reader :organization, :user, :external_identity

      def saml_user_data
        external_identity.saml_user_data.to_a
      end

      def scim_user_data
        external_identity.scim_user_data.to_a
      end

      def pretty(object)
        GitHub::JSON.encode(object, pretty: true)
      end

      def authorized_tokens
        @authorized_credentials ||=
        begin
          authorized_tokens = authorized_credentials.select(&:using_personal_access_token?)
          authorized_keys = authorized_credentials.select(&:using_public_key?)
          (authorized_tokens + authorized_keys).map(&:credential)
        end
      end

      def ssh_permissions_text(ssh_key)
        "— #{(ssh_key.read_only? ? "Read-only" : "Read/write")}"
      end

      private

      def authorized_credentials
        ::Organization::CredentialAuthorization.
          by_organization(organization: organization).
          by_actor(actor: user).
          active
      end
    end
  end
end
