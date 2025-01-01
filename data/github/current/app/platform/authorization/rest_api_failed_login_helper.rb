# typed: strict
# frozen_string_literal: true

module Platform
  module Authorization
    module RestApiFailedLoginHelper
      extend T::Helpers
      extend T::Sig

      abstract!

      sig { abstract.params(status: T.untyped, options: T.untyped).void }
      def deliver_error!(status, options = {}); end

      # Deliver appropriate response for the login failure.
      #
      # Renders 403 if the rate limit has been exceeded, 401 otherwise.
      sig { params(auth_result: GitHub::Authentication::Result).void }
      def reject_failed_login!(auth_result)
        if auth_result.at_auth_limit_failure?
          reject_for_exceeding_auth_limit!
        elsif auth_result.weak_password_failure?
          reject_for_weak_password!
        elsif auth_result.api_with_password_failure?
          reject_for_api_with_password!
        else
          reject_for_bad_credentials!
        end
      end

      sig { void }
      def reject_for_exceeding_auth_limit!
        GitHub.dogstats.increment("api.authentication", tags: ["reason:locked-out"])
        deliver_error! 403, message: "Maximum number of login attempts exceeded. Please try again later."
      end

      sig { void }
      def reject_for_weak_password!
        GitHub.dogstats.increment("api.authentication", tags: ["reason:weak-password"])
        password_update_url = UrlHelpers.settings_security_url(host: GitHub.host_name)
        deliver_error! 401, message: "Weak credentials. Update your password: #{password_update_url}", documentation_url: "#{GitHub.help_url}/articles/creating-a-strong-password"
      end

      sig { void }
      def reject_for_api_with_password!
        GitHub.dogstats.increment("api.authentication", tags: ["reason:api-password-auth"])
        create_pat_url = UrlHelpers.settings_user_tokens_url(host: GitHub.host_name)
        deliver_error! 401, message: "Bad credentials. The API can't be accessed using username/password authentication. Please create a personal access token to access this endpoint: #{create_pat_url}", documentation_url: "#{GitHub.help_url}/articles/creating-a-personal-access-token-for-the-command-line"
      end

      sig { void }
      def reject_for_bad_credentials!
        GitHub.dogstats.increment("api.authentication", tags: ["reason:invalid"])
        deliver_error! 401, message: "Bad credentials"
      end

      sig { void }
      def reject_for_suspended_user!
        GitHub.dogstats.increment("api.authentication", tags: ["reason:suspended"])
        deliver_error! 403, message: "Sorry. Your account was suspended."
      end

      sig { void }
      def reject_for_suspended_oauth_application!
        GitHub.dogstats.increment("api.authentication", tags: ["reason:suspended-application"])
        deliver_error! 403, message: "Sorry. Your application was suspended. Please contact #{GitHub.support_link_text}"
      end

      sig { void }
      def reject_for_suspended_integration!
        GitHub.dogstats.increment("api.authentication", tags: ["reason:suspended-application"])
        deliver_error! 403, message: "Sorry. This integration was suspended. Please contact #{GitHub.contact_support_url}"
      end

      sig { params(message: String).void }
      def reject_for_suspended_installation!(message)
        GitHub.dogstats.increment("api.authentication", tags: ["reason:suspended-installation"])
        deliver_error! 403, message: message
      end

      sig { params(message: String).void }
      def reject_for_application_owned_by_spammy!(message)
        GitHub.dogstats.increment("api.authentication", tags: ["reason:app-owned-by-spammy"])
        deliver_error! 403, message: message
      end
    end
  end
end
