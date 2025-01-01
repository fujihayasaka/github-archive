# typed: true
# frozen_string_literal: true

if GitHub.enterprise?
  module ApplicationController::EnterpriseDependency
    extend ActiveSupport::Concern
    extend T::Helpers
    requires_ancestor { ApplicationController }

    included do
      T.bind(self, T.class_of(ApplicationController))
      helper_method :enterprise?
      helper_method :enterprise_license
      helper_method :enterprise_certificate
      helper_method :enterprise_first_run?
      helper_method :renew_license_url
    end

    PRIVATE_MODE_IGNORE_PATHS = %r{\A(
      # Signup flow
      /join|
      /signup_check/.*|

      # Authentication
      /login(/.*)?|
      /logout|
      /sessions?(/.*)?|
      /auth/.*|
      /saml/.*|
      /dashboard|
      /dashboard/logged_out|
      /password_reset(/.*)?|
      /users/password|
      /u2f/trusted_facets|
      /u2f/login_fragment|

      # Web app manifest file
      /manifest\.json|

      # Suspended users get sent here
      /suspended|

      # DashboardController ATOM/JSON feeds.
      /[a-z0-9][a-z0-9-]*\.private(\.actor)?\.(atom|json)|

      # Notifications endpoint for marking read email notifications as read.
      /notifications/beacon/.*\.gif|

      # Stafftools reports may be accessed via the trusted port without
      # authentication. Other traffic requires authentication, so skipping private
      # mode shouldn't be a problem.
      /stafftools/reports(/.*)?|

      # GitHub for Windows uses this to determine whether a host is an
      # enterprise instance or not (separate sign in flow to support 2fa)
      # See https://github.com/github/Windows/issues/3431
      /site/sha|

      # Integration tests use this to get the API URL for the tenant
      /site/metadata|

      # For monitoring
      /status
    )\Z}x

    # Helper method for all controllers.
    def enterprise?
      true
    end

    class_methods do
      def enterprise?
        true
      end
    end

    # Check to see if Private Mode is enabled. If enabled, send the user to the
    # login page unless it's the first run.
    def enforce_private_mode
      return unless enforce_private_mode?

      return_to = params[:return_to]
      return_to ||= request.url if request.url.chomp("/") != GitHub.url.chomp("/")
      redirect_to_login(return_to)
    end

    def enforce_private_mode?
      GitHub.private_mode_enabled? &&
        !private_mode_authenticated? &&
        !enterprise_first_run? &&
        request.path_info !~ PRIVATE_MODE_IGNORE_PATHS
    end

    def private_mode_authenticated?
      logged_in? || GitHub::PrivateModeMiddleware.valid_private_mode_session?(cookies)
    end

    def license_invalid_check
      if !enterprise_license.valid?
        render "site/invalid_license", status: 402
      end
    end

    # Check to see if referrer policy should be overridden for Enterprise instance.
    # Only available for Enterprise Server.
    def override_referrer_policy
      return unless GitHub.single_business_environment?
      if GitHub.global_business.referrer_override_enabled?
        set_same_origin_referrer_policy
      end
    end

    def renew_license_url
      return DotcomConnection.new.dotcom_enterprise_licensing_url if enterprise_license.metered?
      GitHub.enterprise_web_url + "/expired"
    end

    # Early before filter responds with a simple "App Expired" page when
    # the enterprise license is expired.
    def license_expiration_check
      if enterprise_license.expired?
        render "site/expired", status: 402
      end
    end

    def first_run_check
      if enterprise_first_run?
        if GitHub.first_run_exempt_from_signup?
          redirect_to_login
        else
          redirect_to signup_path
        end
      end
    end

    # Object providing logic and a bunch of helper methods around license
    # expiration and seats.
    #
    # See GitHub::Enterprise::License for available methods.
    def enterprise_license
      GitHub::Enterprise.license
    end

    # Provides logic related to the TLS certificate of a GitHub Enterprise
    # installation.
    #
    # See GitHub::Enterprise::Certificate for more.
    def enterprise_certificate
      GitHub::Enterprise.certificate
    end

    # Is the app in first run mode? True only when no user exists yet.
    def enterprise_first_run?
      GitHub.enterprise_first_run?
    end
  end
else
  module ApplicationController::EnterpriseDependency
    extend ActiveSupport::Concern
    extend T::Helpers
    requires_ancestor { ApplicationController }

    included do
      T.bind(self, T.class_of(ApplicationController))
      helper_method :enterprise?
    end

    class_methods do
      def enterprise?
        false
      end
    end

    def enterprise?
      false
    end
  end
end
