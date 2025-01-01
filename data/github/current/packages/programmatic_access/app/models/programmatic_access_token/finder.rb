# typed: true
# frozen_string_literal: true

module ProgrammaticAccessToken
  class Finder
    CATALOG_SERVICE = "github/apps"
    ACTOR_TYPE = "User"
    SUCCESS_RESULT = :RESULT_SUCCESS

    # https://github.com/github/authnd/blob/fb211bc3b6339aecba57309d46774cd90644d843/client/proto/authentication/v0/helpers.go#L8
    TOKEN_TYPE = "ProgrammaticAccessToken"

    def initialize(access)
      @access = access
    end

    def self.perform(access)
      new(access).perform
    end

    def perform
      find_credentials_response = with_tenant_context do
        credential_manager.find_credentials(TOKEN_TYPE, {
          "actor.id" => @access.user_id,
          "actor.type" => ACTOR_TYPE,
          "access.id" => @access.id,
        })
      end

      unless find_credentials_response.result == SUCCESS_RESULT
        raise Result::Error, find_credentials_response.error
      end

      credentials = find_credentials_response.credentials.map { |credential| ProgrammaticAccessToken::Credential.new_from_protobuff(credential) }

      Result.success(credentials)
    rescue ::Authnd::Proto::Error, Faraday::Error, Result::Error => err
      Failbot.report!(err)
      Result.failed(err.message)
    end

    private

    def credential_manager
      ::GitHub::Authnd.credential_manager_for(CATALOG_SERVICE)
    end

    def with_tenant_context
      return yield unless GitHub::CurrentTenant.stafftools_tenant?

      stafftools_tenant = GitHub::CurrentTenant.get
      business = GitHub::CurrentTenant.unscope { @access.owner.enterprise_managed_business }

      response = GitHub::CurrentTenant.set(business) do
        yield
      end
      GitHub::CurrentTenant.set(stafftools_tenant)

      response
    end
  end
end
