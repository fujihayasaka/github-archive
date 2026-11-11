#!/usr/bin/env ruby
# typed: true
# frozen_string_literal: true

require "sorbet-runtime"
require "faraday"
require "json"
require "uri"

module GitHub
  module QueryGuard
    module Azure
      extend self

      class Auth

        attr_reader :tenant_id, :client_id, :token_uri

        sig { params(tenant_id: T.nilable(String), client_id: T.nilable(String)).void }
        def initialize(tenant_id: nil, client_id: nil)
          @tenant_id = tenant_id
          @client_id = client_id

          @tokens = {}
          @expiries = {}
          @token_uri = URI.parse("https://login.microsoftonline.com/#{@tenant_id}/oauth2/v2.0/token")
        end

        sig { params(scope: String, force_refresh: T::Boolean).returns(T.nilable(String)) }
        def access_token(scope:, force_refresh: false)
          return @tokens[scope] if !force_refresh && valid_token?(scope)

          token_response = fetch_access_token(scope)
          return unless token_response

          @tokens[scope] = token_response["access_token"]
          @expiries[scope] = Time.now.utc + token_response["expires_in"].to_i
          @tokens[scope]
        end

        private

        sig { params(scope: String).returns(T.nilable(T::Hash[String, String])) }
        def fetch_access_token(scope)
          oidc_token = fetch_oidc_token
          unless oidc_token
            warn "Failed to acquire OIDC token from GitHub Actions"
            return
          end

          conn = Faraday.new(url: token_uri) # rubocop:disable GitHub/RequireExplicitInternalOrExternalFaradayClientWrapper
          response = conn.post do |req|
            req.body = {
              grant_type: "client_credentials",
              client_id: client_id,
              client_assertion_type: "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
              client_assertion: oidc_token,
              scope: scope
            }
            req.headers["Content-Type"] = "application/x-www-form-urlencoded"
          end

          unless response.success?
            warn "Failed to acquire access token: #{response.status} - #{response.body}"
            return
          end

          JSON.parse(response.body)
        end

        sig { returns(T.nilable(String)) }
        def fetch_oidc_token
          request_url = ENV["ACTIONS_ID_TOKEN_REQUEST_URL"]
          request_token = ENV["ACTIONS_ID_TOKEN_REQUEST_TOKEN"]

          unless request_url && request_token
            warn "ACTIONS_ID_TOKEN_REQUEST_URL or ACTIONS_ID_TOKEN_REQUEST_TOKEN not set"
            return
          end

          uri = URI.parse(request_url)
          params = URI.decode_www_form(uri.query || "")
          params << ["audience", "api://AzureADTokenExchange"]
          uri.query = URI.encode_www_form(params)

          conn = Faraday.new(url: uri) # rubocop:disable GitHub/RequireExplicitInternalOrExternalFaradayClientWrapper
          response = conn.get do |req|
            req.headers["Authorization"] = "Bearer #{request_token}"
            req.headers["Accept"] = "application/json; api-version=2.0"
          end

          unless response.success?
            warn "Failed to fetch OIDC token: #{response.status} - #{response.body}"
            return
          end

          JSON.parse(response.body)["value"]
        end

        sig { params(scope: String).returns(T.untyped) }
        def valid_token?(scope)
          @tokens[scope] && @expiries[scope]&.>(Time.now.utc)
        end
      end

      sig { params(auth: Auth, scope: String, max_retries: Integer, block: T.proc.params(token: T.nilable(String)).returns(T.untyped)).returns(T.untyped) }
      def with_auth(auth:, scope:, max_retries: 1, &block)
        retries = 0
        begin
          token = auth.access_token(scope: scope, force_refresh: retries.positive?)
          block.call(token)
        rescue Faraday::UnauthorizedError, Faraday::ClientError => e
          retries += 1
          Kernel.raise e if retries > max_retries
          retry
        end
      end

      # Thin Kusto query client.
      class Kusto

        sig { params(auth: Auth, cluster_url: String).void }
        def initialize(auth, cluster_url)
          @auth = auth
          @cluster_url = cluster_url
          @scope = URI.join(cluster_url, "/.default").to_s
          @url = "#{@cluster_url}/v2/rest/query"
        end

        sig { params(query_text: String, db: String).returns(T::Array[T.untyped]) }
        def query(query_text, db)
          body = { db: db, csl: query_text }

          response = Azure.with_auth(auth: @auth, scope: @scope) do |token|
            puts "Querying Kusto: #{query_text}\n\n"
            conn = Faraday.new(url: URI.parse(@url)) do |f| # rubocop:disable GitHub/RequireExplicitInternalOrExternalFaradayClientWrapper
              f.request :authorization, "Bearer", token
              f.request :json
              f.response :json
              f.response :raise_error
              f.adapter Faraday.default_adapter
            end

            conn.post do |req|
              req.body = body.to_json
            end
          end

          response.body[2]["Rows"]
        end
      end

      # Event Hub ingestion client.
      class EventHub

        sig { params(auth: Auth, event_hub_namespace: String, event_hub_path: String).void }
        def initialize(auth, event_hub_namespace, event_hub_path)
          @auth = auth
          @event_hub_namespace = event_hub_namespace
          @event_hub_path = event_hub_path
          @scope = "https://eventhubs.azure.net/.default"
          @url = "https://#{@event_hub_namespace}.servicebus.windows.net/#{@event_hub_path}/messages"
        end

        sig { params(messages: T::Array[T.untyped], table: String).void }
        def ingest(messages:, table:)
          body = messages.map { |message| map_message(message, table) }

          Azure.with_auth(auth: @auth, scope: @scope) do |token|
            conn = Faraday.new(url: URI.parse(@url)) do |f| # rubocop:disable GitHub/RequireExplicitInternalOrExternalFaradayClientWrapper
              f.request :authorization, "Bearer", token
              f.request :json
              f.response :json
              f.adapter Faraday.default_adapter
            end

            conn.post do |req|
              req.headers["Content-Type"] = "application/vnd.microsoft.servicebus.json"
              req.body = body.to_json
            end
          end
        end

        private

        sig { params(message: T.untyped, table: String).returns(T::Hash[Symbol, T.untyped]) }
        def map_message(message, table)
          {
            Body: message.to_json,
            UserProperties: {
              Encoding: "UTF-8",
              Format: "JSON",
              IngestionMappingReference: "default",
              Table: table,
            }
          }
        end
      end
    end
  end
end
