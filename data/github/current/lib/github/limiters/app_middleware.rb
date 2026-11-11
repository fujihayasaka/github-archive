# typed: true
# frozen_string_literal: true

module GitHub
  module Limiters

    # Internal: These paths skip limiting completely.
    #
    # /status is used internally by haproxy to determine if workers are alive.
    # /site/sha is used internally by amen for monitoring
    #
    # Allow otherwise-abusive requests to /login and /login/oauth/*. For
    # example, a shared office with a misconfigured script requiring
    # authentication would not block the rest of the users on the same IP from
    # logging in or authenticating with oauth.
    #
    # Avatar and key files are allowlisted to allow automated scripts like chef
    # to load keys files, and for the atom plugins manager to load avatars
    # without being rate-limited.
    #
    # Login attempts are also rate-limited elsewhere.
    IGNORED_PATHS = %r(\A( /status                  # internal haproxy check
                          |/site/sha                # internal amen check
                          |/login(/oauth/\w+)?      # login/oauth on dotcom
                          |/auth/github(/callback)? # oauth on gist
                          |/[^/]+\.(png|keys)       # avatar/keys files
                         )\Z)x

    # Internal: User-agent for nugget requests
    NUGGET_USER_AGENT = %r(\bnugget/\d+\.\d+\.\d+\b)

    # Public: This subclass allowlists some app paths.
    class AppMiddleware < GitHub::Limiters::Middleware
      class Disabled < AppMiddleware
        # Disabled by default, but with a query string override for testing
        sig { params(env: T::Hash[T.untyped, T.untyped]).returns(T::Boolean) }
        def enabled?(env)
          env.fetch(QUERY_STRING, "").include?("enable-limiters")
        end
      end

      sig { params(app: T.untyped, limiters: T.untyped).void }
      def initialize(app, *limiters)
        super(*T.unsafe([app, "app", *limiters]))
      end

      protected

      sig { params(env: T.untyped).returns(T::Boolean) }
      def enabled?(env)
        GitHub.request_limiting_enabled?
      end

      sig { params(env: T.untyped).returns(T::Boolean) }
      def ignored?(env)
        super || ignored_path?(env) || nugget_request?(env) || octocaptcha_request?(env)
      end

      sig { params(env: T.untyped).returns(T::Boolean) }
      def ignored_path?(env)
        IGNORED_PATHS.match? env[PATH_INFO]
      end

      OCTOCAPTCHA_HOST = "octocaptcha.com"
      OCTOCAPTCHA_TEST_PATH = "/octocaptcha_test"

      sig { params(env: T.untyped).returns(T::Boolean) }
      def octocaptcha_request?(env)
        env[HTTP_X_FORWARDED_HOST] == OCTOCAPTCHA_HOST && env[PATH_INFO] == OCTOCAPTCHA_TEST_PATH
      end

      # Nugget makes requests to `/` on gist.github.com with a nugget user
      # agent. Make sure those are allowed.
      sig { params(env: T.untyped).returns(T::Boolean) }
      def nugget_request?(env)
        (env[HTTP_USER_AGENT] || "").match? NUGGET_USER_AGENT
      end
    end
  end
end
