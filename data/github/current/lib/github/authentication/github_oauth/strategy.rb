# typed: true
# frozen_string_literal: true

module GitHub
  module Authentication
    class GitHubOauth
      require "oa-core"

      class Strategy
        include ::OmniAuth::Strategy

        # Faraday client errors mean OAuth isn't able to talk to the GitHub API.
        # This is likely because a firewall rule in enterprise is preventing
        # access, or that GitHub itself is down.
        def call!(env)
          super
        rescue Faraday::Error
          [503, { "Content-Type" => "text/html" }, File.open("#{Rails.root}/public/enterprise/503-external.html")]
        end

        def initialize(app, options = {}, &block)
          super(app, :github_oauth, options, &block)

          @client_options = {
            site: "https://api.github.com",
            authorize_url: "https://github.com/login/oauth/authorize",
            token_url: "https://github.com/login/oauth/access_token",
          }
          GitHub::Authentication.logger.info("code.namespace" => self.class.name, "code.function" => __method__, "oauth.strategy.options" => options, "oauth.strategy.configuration" => @configuration)
        end

        def client
          ::OAuth2::Client.new(T.unsafe(self).options[:client_id], T.unsafe(self).options[:client_secret], @client_options)
        end

        protected

        def request_phase
          qparams = { client_id: T.unsafe(self).options[:client_id], scope: "user" }
          return_to = request.params["return_to"]

          auth_path = "auth/github_oauth/callback?return_to=#{return_to}"

          qparams["redirect_uri"] = "#{request.scheme}://#{request.host}/#{auth_path}" if return_to

          redirect client.auth_code.authorize_url(qparams)
        end

        def callback_phase
          if request.params["error"] || request.params["error_reason"]
            raise CallbackError.new(request.params["error"], request.params["error_description"] || request.params["error_reason"], request.params["error_uri"])
          end

          access_token = build_access_token(request)
          user = UserInfo.load(access_token.token)

          if user.authorized?(T.unsafe(self).options[:github_organization])
            T.unsafe(self).env["omniauth.auth"] = {
            "uid" => user.login,
            "user_info" => user }.with_indifferent_access

            call_app!
          else
            redirect File.join(GitHub.url, "dashboard")
          end
        end

        def build_access_token(request)
          verifier = request.params["code"]
          params = {
            client_id: T.unsafe(self).options[:client_id],
            client_secret: T.unsafe(self).options[:client_secret],
          }
          client.auth_code.get_token(verifier, params)
        end

        # An error that is indicated in the OAuth 2.0 callback.
        # This could be a `redirect_uri_mismatch` or other
        class CallbackError < StandardError
          attr_accessor :error, :error_reason, :error_uri

          def initialize(error, error_reason = nil, error_uri = nil)
            self.error = error
            self.error_reason = error_reason
            self.error_uri = error_uri
          end

          def message
            [error, error_reason, error_uri].compact.join(" | ")
          end
        end
      end
    end
  end
end
