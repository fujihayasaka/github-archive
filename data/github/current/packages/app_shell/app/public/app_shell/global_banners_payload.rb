# typed: strict
# frozen_string_literal: true

module AppShell
  class GlobalBannersPayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "globalBannersRoute"
    end

    sig { params(flash: T.nilable(T::Array[[String, String]]), sso_orgs: T.nilable(T::Array[T::Hash[Symbol, String]])).void }
    def initialize(flash: nil, sso_orgs: nil)
      @flash = flash
      @sso_orgs = sso_orgs
    end

    sig { override.returns(T::Hash[T.untyped, T.untyped]) }
    def payload
      {
        flashMessages: @flash,
        ssoOrgs: @sso_orgs
      }
    end
  end
end
