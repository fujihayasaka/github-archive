# typed: true
# frozen_string_literal: true

module GitHub

  # GitHub authentication adapters
  #
  # The Default adapter is used by github.com and any enterprise instance
  # that uses 'GitHub' authentication. Provides a common interface for
  # all authentication schemes used by any type of request (web, API,
  # gerve, etc.).
  module Authentication
    autoload :Attempt, "github/authentication/attempt"
    autoload :CAS, "github/authentication/cas"
    autoload :Default, "github/authentication/default"
    autoload :Feed, "github/authentication/feed"
    autoload :GitHubOauth, "github/authentication/github_oauth"
    autoload :LDAP, "github/authentication/ldap"
    autoload :LogoutResult, "github/authentication/logout_result"
    autoload :OmniAuth, "github/authentication/omniauth"
    autoload :Result, "github/authentication/result"
    autoload :SAML, "github/authentication/saml"
    autoload :SignedAuthToken, "github/authentication/signed_auth_token"
    autoload :TokenLookup, "github/authentication/token_lookup"
    autoload :UserHandler, "github/authentication/user_handler"
    autoload :KV, "github/authentication/kv"

    include GitHub::Telemetry::Logs::Loggable

    AUTH_MODES = [
      :cas,
      :default,
      :github_oauth,
      :ldap,
      :saml,
    ]

    module GitAuth
      autoload :SignedAuthToken,      "github/authentication/git_auth/signed_auth_token"
    end
  end
end
