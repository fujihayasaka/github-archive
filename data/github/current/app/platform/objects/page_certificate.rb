# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PageCertificate < Platform::Objects::Base
      description "A TLS certificate for a given GitHub Pages custom domain."

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
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      visibility :internal
      scopeless_tokens_as_minimum

      field :domain, String, description: "Identifies the domain which the certificate belongs to.", null: false

      field :alt_domain, String, description: "Identifies the alternate domain which the certificate belongs to.", null: false

      field :state, Enums::PageCertificateState, method: :current_state, description: "Identifies the current state in the request process the certificate is in.", null: true

      field :state_detail, String, description: "Provides greater detail related to the state, such as an error message.", null: true

      # These are kind of internal-only, and don't really seem useful to outsiders.
      field :expires_at, Scalars::DateTime, visibility: :internal, description: "Identifies when the certificate expires.", null: true

      field :challenge_path, Scalars::URI, description: "Identifies the URL path that our certificate provider will request to prove our ownership of the domain.", null: true, visibility: :internal

      field :challenge_response, String, visibility: :internal, description: "Identifies the response that our certificate provider expects when it requests the challengePath.", null: true

      field :alt_challenge_path, Scalars::URI, description: "Identifies the URL path that our certificate provider will request to prove our ownership of the alternate domain.", null: true, visibility: :internal

      field :alt_challenge_response, String, visibility: :internal, description: "Identifies the response that our certificate provider expects when it requests the alternate challengePath.", null: true

      field :fastly_private_key_id, String, visibility: :internal, method: :fastly_privkey_id, description: "Identifies the private key used to generate the certificate as Fastly names it.", null: true
    end
  end
end
