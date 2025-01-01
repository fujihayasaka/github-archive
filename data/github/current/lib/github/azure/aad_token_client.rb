# typed: true
# frozen_string_literal: true

module GitHub
  module Azure
    class AadTokenClient
      # Will renew the token within this number of seconds before it expires
      EXPIRATION_SAFE_THRESHOLD_SECONDS = 60
      HEADERS = { "Content-Type" => "application/x-www-form-urlencoded" }
      GRAPH_SCOPE = "https://graph.microsoft.com/.default"

      # object_id is the application's object_id, not the service principal's one
      def initialize(tenant_id:, client_id:, client_secret:, object_id:, scope:)
        @token_url = "https://login.microsoftonline.com/#{tenant_id}/oauth2/v2.0/token"
        @client_id = client_id
        @client_secret = client_secret
        @object_id = object_id
        @scope = scope
        @http_client = GitHub::Azure::HttpClient.new
        @client_secret_expiry_checked = false
      end

      def token
        requested_at = Time.now.to_i
        if @token.nil? || requested_at >= @token_expires_at
          @token = @http_client.send_request(method: :post,
            uri: @token_url,
            body: request_body(@scope),
            headers: HEADERS
          ).body
          @token_expires_at = requested_at + @token[:expires_in] - EXPIRATION_SAFE_THRESHOLD_SECONDS
          check_secret_expiry
        end
        @token[:access_token]
      end

      def token_expired?
        return true if @token.nil?
        Time.now.to_i >= @token_expires_at
      end

      private

      def request_body(scope)
        URI.encode_www_form({
          "grant_type" => "client_credentials",
          "client_id" => @client_id,
          "client_secret" => @client_secret,
          "scope" => scope
        })
      end

      def check_secret_expiry
        if !@client_secret_expiry_checked
          begin

            # Get token for the graph API scope, unfortunately this API does not support multiple scopes
            token = @http_client.send_request(method: :post,
              uri: @token_url,
              body: request_body(GRAPH_SCOPE),
              headers: HEADERS
            ).body

            # Get expiry date
            credentials_info = @http_client.send_request(method: :get,
              uri: "https://graph.microsoft.com/v1.0/applications/#{@object_id}/passwordCredentials",
              headers: { "Authorization" => "Bearer #{token[:access_token]}" }
            ).body
            expiry_date_time = credentials_info[:value].first[:endDateTime]
            expires_in_days = (DateTime.iso8601(expiry_date_time) - DateTime.now).to_i

            # Emit number of days before expiry so we can alert
            GitHub.dogstats.gauge("azure.auth.client_id.#{@object_id}.expires_in_days", expires_in_days)
          rescue Faraday::Error, Errno::ETIMEDOUT, Timeout::Error => e
            GitHub::Logger.log_exception({ fn: "#{self.class.name}#check_secret_expiry", error: "Cannot check client secret expiration date" }, e)
          end

          # Always make only 1 attempt per deployment, no need to check for expiry often
          @client_secret_expiry_checked = true
        end
      end
    end
  end
end
