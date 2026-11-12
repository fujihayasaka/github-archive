# frozen_string_literal: true

require_relative "./service_client_base"

require "google/protobuf/well_known_types"

module Authnd
  module Client
    class IdentityManager < ServiceClientBase
      # Issues an identity token with the given claims and optional lifetime.
      #
      # - claims: an Authnd::Proto::Claims message
      # - lifetime: (optional) token lifetime in seconds as a Numeric, or nil for the default (6 hours)
      # - headers: (optional) additional headers to send with the request
      def issue_identity_token(claims, lifetime: nil, headers: {})
        raise ArgumentError, "claims must be an Authnd::Proto::Claims" unless claims.is_a?(Authnd::Proto::Claims)
        raise ArgumentError, "lifetime must be a Numeric" unless lifetime.nil? || lifetime.is_a?(Numeric)

        request = Authnd::Proto::IssueIdentityTokenRequest.new(claims: claims)

        request.lifetime = Google::Protobuf::Duration.new(seconds: lifetime.to_i) if lifetime

        twirp_resp = @twirp_client.issue_identity_token(request, headers: headers)
        raise Authnd::Proto::Error.new(twirp_error: twirp_resp.error) if twirp_resp.error

        twirp_resp.data
      end

      def discovery_document(headers: {})
        request = Authnd::Proto::DiscoveryDocumentRequest.new

        twirp_resp = @twirp_client.discovery_document(request, headers: headers)
        raise Authnd::Proto::Error.new(twirp_error: twirp_resp.error) if twirp_resp.error

        twirp_resp.data
      end

      def jwks(headers: {})
        request = Authnd::Proto::JwksRequest.new

        twirp_resp = @twirp_client.jwks(request, headers: headers)
        raise Authnd::Proto::Error.new(twirp_error: twirp_resp.error) if twirp_resp.error

        twirp_resp.data
      end

      protected

      def create_twirp_client(connection)
        Authnd::Proto::IdentityManagerClient.new(connection)
      end
    end
  end
end
