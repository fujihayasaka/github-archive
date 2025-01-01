# typed: strict
# frozen_string_literal: true

module OauthAccessTokens
  module IOauthAccess
    extend T::Helpers

    include Kernel

    abstract!

    sig { abstract.returns(Integer) }
    def id; end

    sig { abstract.returns(Integer) }
    def user_id; end

    sig { abstract.returns(T.nilable(Users::IUser)) }
    def user; end

    sig { abstract.returns(T.nilable(T.any(OauthApplication, ScopedIntegrationInstallation, SiteScopedIntegrationInstallation))) }
    def application; end

    sig { abstract.returns(T.nilable(OauthApplication)) }
    def oauth_application; end

    sig { abstract.returns(T.nilable(T.any(ScopedIntegrationInstallation, SiteScopedIntegrationInstallation))) }
    def installation; end

    sig { abstract.returns(T.nilable(Integration)) }
    def integration; end

    # collection of Organization::CredentialAuthorizations
    sig { abstract.returns(T.untyped) }
    def credential_authorizations; end

    sig { abstract.returns(String) }
    def hashed_token; end

    sig { abstract.returns(String) }
    def code; end

    sig { abstract.returns(String) }
    def description; end

    sig { abstract.returns(String) }
    def token_last_eight; end

    sig { abstract.returns(ActiveSupport::TimeWithZone) }
    def issued_at; end

    sig { abstract.returns(ActiveSupport::TimeWithZone) }
    def created_at; end

    sig { abstract.returns(ActiveSupport::TimeWithZone) }
    def accessed_at; end

    sig { abstract.returns(T::Boolean) }
    def accessed_at?; end

    sig { abstract.returns(ActiveSupport::TimeWithZone) }
    def expires_at; end

    sig { abstract.returns(T.nilable(Integer)) }
    def expires_at_timestamp; end

    sig { abstract.params(created_by: ActiveSupport::TimeWithZone).returns(T::Boolean) }
    def personal_access_token_eligible_for_account_recovery?(created_by); end

    sig { abstract.returns(T::Array[String]) }
    def scopes; end

    sig { abstract.returns(String) }
    def scopes_string; end

    sig { abstract.returns(String) }
    def pat_type; end

    sig { abstract.returns(String) }
    def pat_type_name; end

    sig { abstract.returns(T.any(Symbol, Integer)) }
    def pat_lifetime_in_days; end

    sig { abstract.params(target: T.untyped).returns(T::Boolean) }
    def pat_adheres_by_targets_expiration_limit?(target); end
  end
end
