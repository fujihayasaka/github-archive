# typed: strict
# frozen_string_literal: true

module ApiInsights::Stats
  class RateLimit
    # This class provides the necessary fields to obtain the rate limits.
    class Context
      sig { returns(T.untyped) }
      attr_reader :request_owner

      sig { returns(T.nilable(OauthApplication)) }
      attr_reader :current_app

      sig { returns(T.nilable(IntegrationInstallation)) }
      attr_reader :current_integration_installation

      sig { returns(T.nilable(Integration)) }
      attr_reader :current_integration

      # These accessors are here to satisfy the requirements of the rate limit configuration.

      sig { returns(T.nilable(User)) }
      attr_reader :current_user

      sig { returns(T.untyped) }
      attr_reader :authenticated_key

      sig { returns(T.untyped) }
      attr_reader :remote_ip

      sig do params(
        request_owner: T.untyped,
        current_app: T.nilable(OauthApplication),
        current_integration_installation: T.nilable(IntegrationInstallation),
        current_integration: T.nilable(Integration)
      ).void
      end
      def initialize(request_owner: nil, current_app: nil, current_integration_installation: nil, current_integration: nil)
        @request_owner = request_owner
        @current_app = current_app
        @current_integration_installation = current_integration_installation
        @current_integration = current_integration

        # Default to nil for these fields.
        @current_user = T.let(nil, T.nilable(User))
        @authenticated_key = T.let(nil, T.untyped)
        @remote_ip = T.let(nil, T.untyped)
      end
    end

    sig { params(family: String).void }
    def initialize(family)
      @family = family
    end

    sig { params(installation: IntegrationInstallation).returns(Integer) }
    def for_installation(installation)
      limit(Context.new(
        current_integration_installation: installation,
        request_owner: installation.target,
      ))
    end

    sig { params(integration: Integration).returns(Integer) }
    def for_integration(integration)
      limit(Context.new(
        current_integration: integration,
        request_owner: integration.owner,
      ))
    end

    sig { params(oauth_access: OauthAccess).returns(Integer) }
    def for_oauth_application(oauth_access)
      limit(Context.new(
        current_app: oauth_access.oauth_application,
        request_owner: oauth_access.user,
      ))
    end

    sig { params(context: Context).returns(Integer) }
    private def limit(context)
      ::Api::RateLimitConfiguration.for(@family, context).limit
    end
  end
end
