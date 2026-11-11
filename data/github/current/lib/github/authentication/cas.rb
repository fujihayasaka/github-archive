# typed: true
# frozen_string_literal: true

module GitHub
  module Authentication
    class CAS < OmniAuth
      require "github/cas/strategy"
      require "github/cas/service_ticket_validator"

      # Since users may be either all external, or a mix of builtin and external,
      # 2FA requirement is never an option for CAS.
      def two_factor_org_requirement_allowed?
        false
      end

      # Public: Determines if a given user is using CAS authentication
      # or if they're using builtin authentication.
      #
      # If the user does not exist locally, assume we are asking about an
      # CAS user whose account has not yet been created.
      #
      # user_of_login - The User itself or their login/email.
      #
      # Returns a Boolean.
      def external_user?(user_or_login)
        return true unless builtin_auth_fallback?

        user = User.reify(user_or_login)
        !!(user.nil? || user.cas_mapping)
      end

      # Public: Returns any mapping information we have on hand, if any, for
      # external users.
      def external_mapping(user)
        user.cas_mapping
      end

      # Alias builtin password authentication so we can override it for SAML but
      # still call it if builtin authentication fallback is enabled.
      alias_method :builtin_password_authenticate, :password_authenticate

      # Public: Attempts to authenticate a user via login and password.
      #
      # The normal CAS flow won't call it, so it returns a failure by default.
      # But if built-in authentication fallback is enabled, OmniAuth#rails_authenticate
      # defers to Default#rails_authenticate, which will try to call this one,
      # so we must defer again to the builtin counterpart.
      #
      # login    - The user login String
      # password - The user password String.
      #
      # Returns a GitHub::Authentication::Result
      def password_authenticate(login, password)
        return builtin_password_authenticate(login, password) if builtin_auth_fallback? && !external_user?(login)

        GitHub::Authentication::Result.failure message: "Password authentication is not supported by CAS authentication."
      end

      # Whether or not to validate a user
      #
      # This is used in the /meta API endpoint in order to signal to our
      # client apps (like Desktop) whether they will be able to authenticate
      # using username and password or if they have to use the oauth web flow
      # for sign in.
      #
      # Returns false for CAS
      def verifiable?
        false
      end

      def sudo_mode_enabled?(user)
        return false unless builtin_auth_fallback?

        !external_user?(user)
      end

      def strategy
        GitHub::Authentication::CAS::Strategy
      end

      def config
        { cas_server: GitHub.cas_url }
      end

      def name
        custom_authentication_name || "CAS"
      end

      # Internal: Overrides user_info from the OmniAuth handler since the CAS strategy
      # stores user info differently than most other OA handlers.
      #
      # omniauth_env  - The "omniauth.env" pulled from the request env.
      #
      # Returns a Hash.
      def user_info(omniauth_env)
        info = omniauth_env.fetch("extra", {})
        info.merge("user" => omniauth_env["uid"])
      end

      def rails_logout(request, current_user, redirect_to: "/")
        if external_user?(current_user)
          return_to = { service: File.join(GitHub.url, redirect_to) }.to_param
          LogoutResult.success "#{GitHub.cas_url}/logout?#{return_to}"
        else
          LogoutResult.success redirect_to
        end
      end

      # Do not redirect on failure if falling back to internal auth
      # so we can display error messages
      def redirect_on_failure?
        !builtin_auth_fallback?
      end

      # Whether or not this authentication strategy allows built-in autentication
      # as a fallback (e.g. Allow users to sign in via SAML or username/password).
      def builtin_auth_fallback?
        GitHub.builtin_auth_fallback
      end

      # Internal: Override find_or_create_user to also create/update the associated
      # CasMapping for the user if we were able to find/create one.
      #
      # uid   - The login String of the user.
      # entry - A Hash providing additional user information returned by CAS.
      #
      # Returns a user and a nil message if a User was found or created.
      # Returns nil and a message if there was an error.
      def find_or_create_user(uid, entry = nil)
        user, msg = super

        record_cas_mapping(user, entry) if user

        [user, msg]
      end

      # Internal: Creates or updates the CasMapping for the given user based
      # on the most recent information returned by CAS.
      #
      # user      - The User for whom to create the mapping.
      # user_info - A Hash providing additional user information returned by CAS.
      #
      # Returns nothing.
      def record_cas_mapping(user, user_info)
        mapping = user.cas_mapping || user.build_cas_mapping
        mapping.update(username: user_info["user"])

        unless mapping.errors.empty?
          GitHub::Authentication.logger.error("code.namespace" => self.class.name, "code.function" => __method__, "gh.enduser.login" => user.login, "exception.message" => mapping.errors.full_messages.to_sentence)
        end
      end
    end
  end
end
