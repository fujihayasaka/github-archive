# typed: true
# frozen_string_literal: true

# The MIT License (MIT)
#
# Copyright (c) 2015 Microsoft Corporation
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
# Portions Copyright (c) GitHub, Inc.

module GitHub
  module Azure
    #
    # Class that provides access to authentication token.
    #
    class ApplicationTokenProvider

      private

      TOKEN_ACQUIRE_URL = "{authentication_endpoint}{tenant_id}/oauth2/token"
      REQUEST_BODY_PATTERN = "resource={resource_uri}&client_id={client_id}&client_secret={client_secret}&grant_type=client_credentials"
      DEFAULT_SCHEME = "Bearer"

      # @return [ActiveDirectoryServiceSettings] settings.
      attr_accessor :settings

      # @return [String] tenant id (also known as domain).
      attr_accessor :tenant_id

      # @return [String] application id.
      attr_accessor :client_id

      # @return [String] application secret key.
      attr_accessor :client_secret

      # @return [String] auth token.
      attr_writer :token

      # @return [Time] the date when the current token expires.
      attr_writer :token_expires_on

      # @return [Integer] the amount of time we refresh token before it expires.
      attr_reader :expiration_threshold

      public

      # @return [Time] the date when the current token expires.
      attr_reader :token_expires_on

      # @return [String] the type of token.
      attr_reader :token_type

      # @return [String] auth token.
      attr_reader :token

      #
      # Creates and initialize new instance of the ApplicationTokenProvider class.
      # @param tenant_id [String] tenant id (also known as domain).
      # @param client_id [String] client id.
      # @param client_secret [String] client secret.
      # @param settings [ActiveDirectoryServiceSettings] active directory setting.
      def initialize(tenant_id, client_id, client_secret, settings)
        fail ArgumentError, "Tenant id cannot be nil" if tenant_id.nil?
        fail ArgumentError, "Client id cannot be nil" if client_id.nil?
        fail ArgumentError, "Client secret key cannot be nil" if client_secret.nil?
        fail ArgumentError, "Azure AD settings cannot be nil" if settings.nil?

        @tenant_id = tenant_id
        @client_id = client_id
        @client_secret = client_secret
        @settings = settings

        @expiration_threshold = 5 * 60
      end

      #
      # Returns the string value which needs to be attached
      # to HTTP request header in order to be authorized.
      #
      # @return [String] authentication headers.
      def get_authentication_header
        acquire_token if token_expired
        "#{token_type} #{token}"
      end

      private

      #
      # Checks whether token is about to expire.
      #
      # @return [Bool] True if token is about to expire, false otherwise.
      def token_expired
        @token.nil? || Time.now >= @token_expires_on + expiration_threshold
      end

      #
      # Retrieves a new authentication token.
      #
      # @return [String] new authentication token.
      def acquire_token
        token_acquire_url = TOKEN_ACQUIRE_URL.dup
        token_acquire_url["{authentication_endpoint}"] = @settings.authentication_endpoint
        token_acquire_url["{tenant_id}"] = @tenant_id

        url = URI.parse(token_acquire_url)

        connection = GitHub::FaradayClient.external("AzureApplicationTokenProvider", url)

        request_body = REQUEST_BODY_PATTERN.dup
        request_body["{resource_uri}"] = ERB::Util.url_encode(@settings.token_audience)
        request_body["{client_id}"] = ERB::Util.url_encode(@client_id)
        request_body["{client_secret}"] = ERB::Util.url_encode(@client_secret)

        response = connection.get do |request|
          request.headers["content-type"] = "application/x-www-form-urlencoded"
          request.body = request_body
        end

        fail StandardError,
          "Couldn't login to Azure, please verify your tenant id, client id and client secret" unless response.status == 200

        response_body = GitHub::JSON.load(response.body)
        @token = response_body["access_token"]
        @token_expires_on = Time.at(Integer(response_body["expires_on"]))
        @token_type = response_body["token_type"]
      end
    end

  end
end
