# typed: false
# frozen_string_literal: true

module GitHub
  module Azure
    class AadCodeGrantTokenClient

      # Will renew the token within this number of seconds before it expires
      EXPIRATION_SAFE_THRESHOLD_SECONDS = 60
      HEADERS = { "Content-Type" => "application/x-www-form-urlencoded" }.freeze
      GRAPH_SCOPE = "https://graph.microsoft.com/.default"

      # object_id is the application's object_id, not the service principal's one
      def initialize(client_id:, client_secret:, scope:, grant_type:, redirect_uri:, code:)
        @token_url = "https://login.microsoftonline.com/common/oauth2/v2.0/token"
        @client_id = client_id
        @client_secret = client_secret
        @scope = scope
        @grant_type = grant_type
        @redirect_uri = redirect_uri
        @code = code

        @http_client = GitHub::Azure::HttpClient.new
      end

      def fetch_token
        requested_at = Time.now.to_i
        if token.nil? || requested_at >= token_expires_at
          self.token = http_client.send_request(method: :post,
            uri: token_url,
            body: request_body(@scope),
            headers: HEADERS
          ).body
        end
        self.token[:access_token]
      end

      private

      attr_reader :token_url, :client_id, :client_secret, :scope, :grant_type, :redirect_uri, :code, :http_client
      attr_accessor :token

      def request_body(scope)
        URI.encode_www_form({
          "grant_type" => "authorization_code",
          "client_id" => @client_id,
          "client_secret" => @client_secret,
          "scope" => scope,
          "redirect_uri" => @redirect_uri,
          "code" => @code
        })
      end
    end
  end
end
