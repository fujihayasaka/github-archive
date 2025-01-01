# frozen_string_literal: true

require_relative "./service_client_base"

module Authnd
  module Client
    class IdentityManager < ServiceClientBase
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
