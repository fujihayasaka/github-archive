# typed: strict
# frozen_string_literal: true

# Renders the Danger zone section of the Credentials settings page: two cards
# whose confirmation dialogs both submit to Settings::CredentialsController#destroy
# with a hidden `revocation_type` of "authorizations" or
# "credentials_and_authorizations" (matching Businesses::CredentialRevocationController).
#
# The count helpers mirror Settings::CredentialsOverviewComponent, but collapse
# its "Authorized OAuth apps" and "Authorized GitHub Apps" rows into a single
# "app access token" row to keep the dialog summary lists short. They are
# memoized because each count is rendered once per dialog (twice per request).
module Settings
  class CredentialsDangerZoneComponent < ApplicationComponent
    sig { returns(User) }
    attr_reader :user

    sig { params(user: User).void }
    def initialize(user:)
      @user = T.let(user, User)
    end

    sig { returns(T::Boolean) }
    def render?
      emu_user? || enterprises?
    end

    sig { returns(T::Boolean) }
    def emu_user?
      user.is_enterprise_managed?
    end

    sig { returns(T::Array[Business]) }
    memoize def enterprises
      user.businesses.to_a
    end

    sig { returns(T::Boolean) }
    def enterprises?
      enterprises.any?
    end

    sig { returns(String) }
    def confirmation_text
      "#{user.display_login} credentials"
    end

    sig { returns(Integer) }
    memoize def fine_grained_personal_access_tokens_count
      ProgrammaticAccess.for(user).count
    end

    sig { returns(Integer) }
    memoize def classic_personal_access_tokens_count
      OauthAccessTokens.domain.personal_tokens_count(user.id)
    end

    sig { returns(Integer) }
    memoize def app_access_tokens_count
      user.oauth_authorizations.oauth_apps.user_revocable(OauthApplication).count +
        user.oauth_authorizations.github_apps.count
    end

    sig { returns(Integer) }
    memoize def ssh_keys_count
      user.public_keys.count
    end
  end
end
