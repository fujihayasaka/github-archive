# typed: true
# frozen_string_literal: true

require "authnd-client"
require "rotp"

module GitHub
  module Authentication
    # Default Authentication a.k.a. GitHub Authentication. Defines the
    # adapter interface and acts as the base adapter.
    class Default

      # Configuration hash
      attr_reader :configuration

      # Public: utility predicate methods to query for adaptor's auth mode.
      # Returns boolean whether this adaptor matches one of
      # GitHub::Authentication::AUTH_MODES. ex: @adaptor.ldap?
      #
      AUTH_MODES.each do |auth_mode|
        define_method "#{auth_mode}?" do
          T.unsafe(self).class.name.demodulize.underscore.to_sym == auth_mode
        end
      end

      # Default initializer. Override for custom initialization.
      def initialize(config = {})
        @configuration = default_config.merge(config)
      end

      # Default configuration hash. Override for custom defaults.
      def default_config
        {}
      end

      # Returns the url to logout. Override this method in subclasses if session
      # is managed externally.
      def logout_url
        "/logout"
      end

      # Authenticate by login, password, and optionally 2FA OTP. This method
      # will validate a user's 2FA OTP if 2FA is enabled for the user.
      #
      # login - The String login of the user to authenticate.
      # password - The String password of the user to authenticate.
      # otp - The OTP of the user to authenticate (optional).
      #
      # Returns a GitHub::Authentication::Result
      def password_and_otp_authenticate(login, password, otp)
        auth_result = password_authenticate(login, password)
        user = auth_result.user

        two_factor_failure =
          auth_result.success? &&
          user.two_factor_authentication_enabled? &&
          !user.valid_otp_for_all_2fa_registrations?(otp, callsite: "password_and_otp_authenticate")

        # If the user is a first EMU admin, does not have 2FA enabled, and the business has SSO configured,
        # we need to prompt the user to the recovery code page as they are "partially" signed in.
        first_emu_admin_recovery_code_failure =
          auth_result.success? &&
          user.is_first_emu_owner? &&
          !user.two_factor_authentication_enabled? &&
          user.enterprise_managed_business&.external_provider_enabled?

        if two_factor_failure
          two_factor_type = user.two_factor_sms_enabled? ? "sms" : "app"
          Result.two_factor_failure user, two_factor_type
        elsif first_emu_admin_recovery_code_failure
          Result.two_factor_failure user, "first_admin_recovery_code"
        else
          auth_result
        end
      end

      # Authenticate by login and password. This method does not consider 2FA,
      # even if it is enabled. This method should only be used for scenarios,
      # such as sudo authentication, where 2FA validation is not required.
      #
      # login - The String login of the user to authenticate.
      # password - The String password of the user to authenticate.
      #
      # Returns a GitHub::Authentication::Result
      def password_authenticate(login, password)
        user, message = User.authenticate(login, password)

        if user && user.suspended?
          Result.suspended_failure message: "Your account has been suspended."
        elsif user
          Result.success user, message: message
        else
          Result.password_failure message: message
        end
      end

      # Authenticate user for sudo access. This method uses
      # GitHub::Authentication::Attempt to inherit functionality, such as rate
      # limiting against brute force attempts.
      #
      # login - The String login of the user to authenticate.
      # password - The String password of the user to authenticate.
      #
      # Returns a GitHub::Authentication::Result
      def sudo_password_authenticate(login, password)
        attempt = GitHub::Authentication::Attempt.new(
          from: :sudo,
          login: login,
          password: password,
        )

        attempt.result
      end

      # Authenticate by an OAuth access token or an integration's installation
      # access token.
      #
      # token                      - The token to use to lookup the associated user.
      # allow_integrations         - Whether the caller supports server to server
      #                              GitHub App authorization checks
      #                              (default false).
      # allow_user_via_granular_actor - Whether the caller supports user to server
      #                              GitHub App authorization checks
      #                              (default false).
      # ip                         - String: The IP address of the request.
      # user_agent                 - String: The User agent header of the request.
      #
      # Returns a GitHub::Authentication::Result
      def access_token_authenticate(token, allow_integrations: false, allow_user_via_granular_actor: false, ip:, user_agent:)
        user = TokenLookup.new(token, ip: ip, user_agent: user_agent).actor

        return Result.token_failure unless user

        token_format = token.include?("_") ? "new" : "old"

        if user.is_a?(Bot) && !allow_integrations
          Result.allow_integrations_failure(
            message: "GitHub App installation tokens are not allowed.",
            token_format: token_format,
          )
        elsif user.using_auth_via_integration? && !allow_user_via_granular_actor
          Result.allow_user_via_granular_actor_failure(
            message: "GitHub App user access tokens are not allowed.",
            token_format: token_format,
          )
        elsif user.suspended?
          Result.suspended_failure message: "Your account has been suspended."
        elsif user.using_auth_via_oauth_application? && user.oauth_application.suspended?
          Result.suspended_oauth_application_failure(
            message: "Your application has been suspended.",
          )
        elsif using_auth_via_suspended_integration?(user)
          Result.suspended_integration_failure(
            message: "This integration has been suspended."
          )
        elsif using_auth_via_application_owned_by_spammy?(user)
          Result.application_owned_by_spammy_failure(
            message: "The owner of this application has been marked as spammy.",
          )
        elsif user.is_a?(Bot) && user.installation.suspended?
          Result.suspended_installation_failure(
            message: suspended_installation_message(user.installation),
          )
        elsif user.using_auth_via_integration? && user.oauth_access.installation&.suspended?
          Result.suspended_installation_failure(
            message: suspended_installation_message(user.oauth_access.installation),
          )
        elsif authenticated_as_attribution_only_system_identity?(user)
          Result.attribution_only_system_identity_failure(
            message: "Attribution-only system identities are not permitted."
          )
        else
          Result.success(user, token_format: token_format)
        end
      end

      def authenticated_as_attribution_only_system_identity?(user)
        integration = if user.using_auth_via_integration?
          user.oauth_access.application
        elsif user.is_a?(Bot)
          user.integration
        end

        Apps::Privileged.capable?(:attribution_only_system_identity, app: integration)
      end

      def using_auth_via_application_owned_by_spammy?(user)
        GitHub.dogstats.distribution_time("api.spammy_owner_check_for_auth_app.time") do
          (user.using_auth_via_oauth_application? && user.oauth_access.application.spammy?) ||  # OAuth Apps
          (user.using_auth_via_integration? && user.oauth_access.application.spammy?) ||        # User-to-Server
          (user.is_a?(Bot) && T.must(user.integration).spammy?)                                         # Server-to-server
        end
      end

      def using_auth_via_suspended_integration?(user)
        integration = if user.using_auth_via_integration?
          user.oauth_access.application
        elsif user.is_a?(Bot)
          user.integration
        end

        return false unless integration

        integration.suspended?
      end

      USER_VIA_GRANULAR_ACTOR_TOKEN_TYPES = {
        "UserToServerToken" => "GitHub App user access tokens are not allowed",
        "ProgrammaticAccessToken" => "Fine-grained personal access tokens are not allowed",
      }.freeze

      # Authenticate against authnd with any access token (e.g. API credential).
      #
      # token                      - The token to use to lookup the associated user.
      # allow_integrations         - Whether the caller supports server to server
      #                              GitHub App authorization checks
      #                              (default false).
      # allow_user_via_granular_actor - Whether the caller supports user to server
      #                              GitHub App authorization checks
      #                              (default false).
      # ip                         - String: The IP address of the request.
      # user_agent                 - String: The User agent header of the request.
      #
      # Returns a GitHub::Authentication::Result
      def access_token_authenticate_authnd(token, access_token_auth_options)
        allow_server_to_server = access_token_auth_options[:allow_server_to_server]
        mesh_available = access_token_auth_options.delete(:mesh_available)
        return (result = Result.token_failure) if !allow_server_to_server && ServerToServerTokens::Domain.matches_pattern?(token)

        return (result = Result.token_failure) unless GitHub::Authnd.valid_token_encoding?(token)

        headers = {}
        if GitHub.flipper[:authnd_publish_oauth_access_events_experiment].enabled?
          headers[::Authnd::Client::ENABLED_FEATURES_HEADER] = ::Authnd::Client.format_enabled_features_for_header(["authnd_publish_oauth_access_events"])
        end
        req = ::Authnd::Proto::AuthenticateRequest::new(
          credentials: ::Authnd::Proto::Credentials::access_token(token))

        resp = ::GitHub::Authnd.authenticator("github/authnd", mesh_available: mesh_available).authenticate(req, headers: headers)

        validate_authnd_access_token_response(token, resp, **access_token_auth_options)
      end

      # Validate the Authnd::Response from an access token authentication request or exchange token verification.
      #
      # token                      - The token to use to lookup the associated user.
      # allow_integrations         - Whether the caller supports server to server
      #                              GitHub App authorization checks
      #                              (default false).
      # allow_user_via_granular_actor - Whether the caller supports user to server
      #                              GitHub App authorization checks
      #                              (default false).
      # ip                         - String: The IP address of the request.
      # user_agent                 - String: The User agent header of the request.
      #
      def validate_authnd_access_token_response(token, resp, allow_integrations: false, allow_user_via_granular_actor: false, allow_server_to_server: false, via_exchange_token: false, ip:, user_agent:)
        return (result = Result.token_failure({ authnd_response: resp })) if resp.result == :RESULT_FAILED_ACCESS_TOKEN_NOT_FOUND
        return (result = Result.suspended_failure({ authnd_response: resp })) if resp.result == :RESULT_FAILED_SUSPENDED
        return (result = Result.application_owned_by_spammy_failure({ authnd_response: resp })) if resp.result == :RESULT_FAILED_APPLICATION_OWNER_SPAMMY
        return (result = Result.token_failure({ authnd_response: resp })) unless resp.success? # handle other unexpected "non-success" results

        token_type = resp.attributes["credential.type"]
        if USER_VIA_GRANULAR_ACTOR_TOKEN_TYPES.key?(token_type) && !allow_user_via_granular_actor
          return (result = Result.allow_user_via_granular_actor_failure(
            message: USER_VIA_GRANULAR_ACTOR_TOKEN_TYPES[token_type],
            authnd_response: resp
          ))
        end

        user = User.find_by(id: resp.attributes["actor.id"])
        return (result = Result.token_failure({ authnd_response: resp })) unless user

        case token_type
        when ProgrammaticAccessTokens::Domain.credential_type
          access = ProgrammaticAccess.for(user).find_by(id: resp.attributes["access.id"])
          return (result = Result.token_failure({ authnd_response: resp })) unless access

          if (proto_timestamp = resp.attributes["credential.expires_at_utc"])
            access.expires_at = proto_timestamp.to_time
          end
          if (proto_timestamp = resp.attributes["credential.issued_at_utc"])
            access.issued_at = proto_timestamp.to_time
          end
          access.bump
          user.programmatic_access = access
        when "ServerToServerToken"
          bot = user.becomes(Bot)

          if !allow_integrations
            return Result.allow_integrations_failure(
              message: "GitHub App installation tokens are not allowed",
            )
          end

          # mimics the behavior in TokenFinder, so we do GTID-based database selection. otherwise, we'll fail to hydrate
          # the installation for recently created scoped or site scoped tokens.
          if user.feature_enabled?(:authnd_server_to_server_db_selection)
            last_operations = DatabaseSelector::LastOperations.from_token(token)
            DatabaseSelector.instance.read_from_database(
              last_operations: last_operations,
              called_from: :token_lookup,
            ) do
              bot.installation =
                if resp.attributes["scoped_installation.type"] == "SiteScopedIntegrationInstallation"
                  SiteScopedIntegrationInstallation.find_by(id: resp.attributes["scoped_installation.id"])
                elsif resp.attributes["scoped_installation.type"] == "ScopedIntegrationInstallation"
                  ScopedIntegrationInstallation.find_by(id: resp.attributes["scoped_installation.id"])
                else
                  IntegrationInstallation.find_by(id: resp.attributes["installation.id"])
                end
            end
          else
            bot.installation =
              if resp.attributes["scoped_installation.type"] == "SiteScopedIntegrationInstallation"
                SiteScopedIntegrationInstallation.find_by(id: resp.attributes["scoped_installation.id"])
              elsif resp.attributes["scoped_installation.type"] == "ScopedIntegrationInstallation"
                ScopedIntegrationInstallation.find_by(id: resp.attributes["scoped_installation.id"])
              else
                IntegrationInstallation.find_by(id: resp.attributes["installation.id"])
              end
          end

          user = bot
        else
          scopes = []
          resp.attributes["credential.scopes"]&.each do |s|
            scopes << s if Api::AccessControl.acceptable_scopes.key?(s)
          end
          user.scopes = scopes

          # we have to hydrate the oauth_access token for token exchange authentication, many things break in the
          # authorizaton stack.
          skip_access_hydration = user.feature_enabled?(:disable_authnd_oauth_access_hydration) && !via_exchange_token
          unless skip_access_hydration
            primary_role = ActiveRecord::Base.connected_to?(role: :writing)
            GitHub.dogstats.increment("authnd.oauth_access_hydration", tags: ["primary:#{primary_role}"])
            user.oauth_access = OauthAccessTokens.domain.by_id(resp.attributes["credential.id"])
          end
        end

        (result = Result.success(user, { authnd_response: resp }))
      ensure
        # if we raised in the method somewhere, result will be nil
        # just treat that as an undefined failure
        result ||= Result.failure

        credential_type = resp&.attributes.try(:fetch, "credential.type", nil)

        # TODO: should we really default to "oauth"?
        # this can be misleading if/when authnd can't respond with a credential type.
        type = case credential_type
        when ProgrammaticAccessTokens::Domain.credential_type
          "programmatic_access"
        when "ServerToServerToken"
          "server_to_server"
        else
          "oauth"
        end

        tags = ["type:#{type}"]
        tags << "credential_type:#{credential_type}" if credential_type
        tags << "authnd_result:#{resp.result}" if resp
        tags << "failure_type:#{result.failure_type}" if result&.failure_type
        tags << "success:#{result.success}" if result

        GitHub.dogstats.increment("gitauth.#{type}_authnd", tags: tags)
      end

      # User lookup & authentication from a rails request.
      #
      # Returns a tuple of a GitHub::Authentication::Result and the User that
      # attempted authentication.
      def rails_authenticate(request, octolytics_id:, current_device_id:)
        attempt = GitHub::Authentication::Attempt.new(
          from: :web,
          login: request.params[:login],
          password: request.params[:password],
          ip: request.remote_ip,
          user_agent: request.user_agent,
          request_id: request.env["HTTP_X_GITHUB_REQUEST_ID"],
          octolytics_id: octolytics_id,
          current_device_id: current_device_id,
        )
        GitHub.dogstats.distribution_time("rails_authenticate.dist.duration") do
          return attempt.result, attempt.attempted_user
        end
      end

      def rails_logout(request, current_user, redirect_to: "/")
        LogoutResult.success redirect_to
      end

      # Built-in GitHub auth vs. an external adaptor (e.g. LDAP, CAS).
      #
      # Returns true for Default, false for any subclass.
      def external?
        false
      end

      # Public: Determines if a given user is using external authentication
      # or if they're using builtin authentication.
      def external_user?(user_or_login)
        false
      end

      # Public: Returns any mapping information we have on hand, if any, for
      # external users.
      def external_mapping(user)
        nil
      end

      # New users are created through the signup page when set. Otherwise,
      # its assumed that users are created externally and they only need to
      # login.
      #
      # Returns true for Default.
      def signup_enabled?
        true
      end

      # Whether or not to validate a user
      #
      # This is used in the /meta API endpoint in order to signal to our
      # client apps (like Desktop) whether they will be able to authenticate
      # using username and password or if they have to use the oauth web flow
      # for sign in.
      #
      # Returns true for the Default authentication provider when not running
      # on GitHub Enterprise unless the brownout_api_basic_auth_blocking feature
      # flag is set
      def verifiable?
        GitHub.api_password_auth_supported?
      end

      def sudo_mode_enabled?(user)
        return false if user&.is_emu_and_not_first_owner?

        true
      end

      # Whether or not this authentication strategy allows built-in authentication
      # as a fallback (e.g. Allow users to sign in via SAML or username/password).
      def builtin_auth_fallback?
        false
      end

      # Whether built-in users are allowed on this strategy / configuration
      def allow_builtin_users?
        !external? || builtin_auth_fallback?
      end

      def two_factor_authentication_enabled?
        allow_builtin_users?
      end

      # Do we allow Organizations to require 2FA for all members?
      def two_factor_org_requirement_allowed?
        two_factor_authentication_enabled?
      end

      def two_factor_authentication_allowed?(user)
        two_factor_authentication_enabled? && !external_user?(user)
      end

      # Public: Whether changing user login is allowed.
      #
      # Returns true if users can change their login names.
      def user_renaming_enabled?(user)
        !external?
      end

      # Public: Whether changing user profile names via the UI is allowed.
      #
      # Returns true as a default and should be defined in the adaptor subclass
      # if different behavior is needed.
      def user_change_profile_name_enabled?(user)
        !profile_name_managed_externally?
      end

      # Public: Whether changing emails via the UI is allowed.
      #
      # Returns true as a default and should be defined in the adaptor subclass
      # if different behavior is needed.
      def user_change_email_enabled?(user)
        !emails_managed_externally?
      end

      # Public: Whether changing SSH keys via the UI is allowed.
      #
      # Returns true as a default and should be defined in the adaptor subclass
      # if different behavior is needed.
      def user_change_ssh_key_enabled?(user)
        !ssh_keys_managed_externally?
      end

      # Public: Whether changing GPG keys via the UI is allowed.
      #
      # Returns true as a default and should be defined in the adaptor subclass
      # if different behavior is needed.
      def user_change_gpg_key_enabled?(user)
        !gpg_keys_managed_externally?
      end

      # Public: Returns true if Profile Names are managed externally
      # Returns false as a default and should be defined in the adaptor subclass
      # if different behavior is needed.
      def profile_name_managed_externally?
        false
      end

      # Public: Returns true if Emails are managed externally
      # Returns false as a default and should be defined in the adaptor subclass
      # if different behavior is needed.
      def emails_managed_externally?
        false
      end

      # Public: Returns true if SSH Keys are managed externally
      # Returns false as a default and should be defined in the adaptor subclass
      # if different behavior is needed.
      def ssh_keys_managed_externally?
        false
      end

      # Public: Returns true if GPG Keys are managed externally
      # Returns false as a default and should be defined in the adaptor subclass
      # if different behavior is needed.
      def gpg_keys_managed_externally?
        false
      end

      # The redirect path for failed authentication. Only used by external adaptors.
      #
      # Returns the route for handling failed auth, or nil if it's not used.
      def path(return_to = nil)
        nil
      end

      # Whether or not to redirect on failed authentication. Defaults to true if
      # `path` is defined.
      def redirect_on_failure?
        path.present?
      end

      def add_middleware(builder)
      end

      def name
        "GitHub"
      end

      # SP XML metadata string used by idP
      def metadata
        metadata = ::SAML::Message::Metadata.new({
          assertion_consumer_service_url: "#{configuration[:sp_url]}/saml/consume",
          sign_assertions: false,
          encrypted_assertions: configuration[:encrypted_assertions],
          issuer: configuration[:sp_url],
        })
        metadata.to_xml
      end

      def instrument(event, payload = {}, &block)
        instrumentation_service.instrument(event, payload, &block)
      end

      def instrumentation_service
        GitHub.instrumentation_service
      end

      # Internal: Determines if the given request looks like it's attempting to authenticate
      # by passing username and password.
      #
      # Returns a Boolean.
      def builtin_auth_attempt?(request)
        request.params.values_at(:login, :password).all?(&:present?)
      end

      # Returns a custom authentication name, if exists
      #
      #
      def custom_authentication_name
        custom_messages = ::CustomMessages.instance
        name = custom_messages.auth_provider_name
        name.presence
      end

      def suspended_installation_message(installation)
        target = installation.target

        if installation.integrator_suspended?
          timestamp = ::Api::Serializer.time(installation.integrator_suspended_at)
          "You suspended this installation owned by #{target.login_for_api} at #{timestamp}"
        elsif installation.user_suspended?
          timestamp = ::Api::Serializer.time(installation.user_suspended_at)
          "Sorry. This installation owned by #{target.login_for_api} suspended your access at #{timestamp}."
        else
          "This GitHub App installation is currently suspended."
        end
      end
    end
  end
end
