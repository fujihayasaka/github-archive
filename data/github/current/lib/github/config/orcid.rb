# typed: strict
# frozen_string_literal: true

module GitHub
  module Config
    # Mixin for the GitHub module that contains all configuration settings related to our ORCID integration.
    #
    # See https://orcid.org/.
    module Orcid
      ORCID_PRODUCTION_HOST = "orcid.org"
      ORCID_SANDBOX_HOST = "sandbox.orcid.org"

      # Access the OAuth client ID associated with a registered ORCID OAuth application, if any.
      sig { returns(T.nilable(String)) }
      def orcid_oauth_client_id
        ENV["ORCID_OAUTH_CLIENT_ID"]
      end

      # Access the OAuth client secret corresponding to the ORCID OAuth client ID, if any.
      sig { returns(T.nilable(String)) }
      def orcid_oauth_client_secret
        ENV["ORCID_OAUTH_CLIENT_SECRET"]
      end

      # Return the hostname of the server to use for ORCID API operations and link generation.
      sig { returns(String) }
      def orcid_host
        @orcid_host ||= T.let(ORCID_PRODUCTION_HOST, T.nilable(String))
      end

      sig { params(orcid_host: T.nilable(String)).void }
      attr_writer :orcid_host

      # Determine whether or not it's appropriate to display ORCID-related configuration options or profile
      # decoration based on the current execution environment. ORCID integration only makes sense on dotcom when
      # appropriate OAuth credentials are available.
      sig { returns(T::Boolean) }
      def orcid_enabled?
        return false if GitHub.enterprise?
        return false if GitHub.multi_tenant_enterprise?

        orcid_oauth_client_id.present? && orcid_oauth_client_secret.present?
      end
    end
  end

  extend Config::Orcid
end
