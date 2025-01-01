# typed: strict
# frozen_string_literal: true

module ServerToServerToken
  class Authenticator
    STATS_KEY = "server_to_server_token.authenticator"

    sig { params(calling_service: String, token: String).returns(::Authnd::Response) }
    def self.perform(calling_service, token)
      new(calling_service, token).perform
    end

    sig { params(calling_service: String, token: String).void }
    def initialize(calling_service, token)
      @calling_service = calling_service
      @token = token
    end

    sig { returns(::Authnd::Response) }
    def perform
      request = ::Authnd::Proto::AuthenticateRequest::new(credentials: ::Authnd::Proto::Credentials::access_token(@token))
      authenticator.authenticate(request)
    end

    private

    sig { returns(::Authnd::Client::Authenticator) }
    def authenticator
      ::GitHub::Authnd.authenticator(@calling_service)
    end
  end
end
