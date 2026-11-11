# typed: true
# frozen_string_literal: true

module ProgrammaticAccessToken
  class Authenticator
    STATS_KEY = "programmatic_access_token.authenticator"

    def self.perform(token)
      new(token).perform
    end

    def initialize(token)
      @token = token
    end

    def perform
      request = ::Authnd::Proto::AuthenticateRequest::new(credentials: ::Authnd::Proto::Credentials::access_token(@token))
      access_token_authenticate_response = authenticator.authenticate(request)

      unless access_token_authenticate_response.success?
        raise Result::Error, access_token_authenticate_response.result
      end

      GitHub.dogstats.increment(STATS_KEY, tags: ["result:success"])
      Result.success(access_token_authenticate_response.attributes["access.id"])
    rescue ::Authnd::Proto::Error, Faraday::Error, Result::Error => err
      GitHub.dogstats.increment(STATS_KEY, tags: ["result:failure"])
      Failbot.report!(err)
      Result.failed(err.message)
    end

    private

    def authenticator
      ::GitHub::Authnd.authenticator
    end
  end
end
