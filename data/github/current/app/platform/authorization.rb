# typed: true
# frozen_string_literal: true

module Platform
  module Authorization
    extend T::Helpers

    requires_ancestor { App::IExecContextAccessor }

    include Platform::Authorization::ConditionalAccessDependency

    ApiChallenge = "github.challenge".freeze
    ApiForbid    = "github.forbid".freeze

    attr_reader :authenticated_key

    BaseAuthorizationTypes = T.type_alias do
      T.any(
        Api::App,
        Api::GraphQL,
      )
    end

    TwirpAuthorizationType = T.type_alias { Api::Internal::Twirp::Registrymetadata::Core::V1::Authorization }

    AuthorizationTypes = T.type_alias do
      T.any(
        BaseAuthorizationTypes,
        TwirpAuthorizationType,
        Platform::Authorization::PermissionCheck,
      )
    end

    # Public: Ensure that the request is authenticated.
    #
    # Halts with a 401 if the request is not authenticated.
    # Returns nothing.
    def require_authentication!
      T.bind(self, BaseAuthorizationTypes)

      unless logged_in?
        deliver_error! 401, documentation_url: "/rest/guides/getting-started-with-the-rest-api#authentication"
      end
    end

    # Public: Checks to see if the current request is authenticated.  This will
    # check the HTTP Authorization header or the `?access_token` OAuth parameter
    # just once.
    #
    # Returns true if the user or key is logged in, or false.
    def logged_in?
      # We don't support anonymous requests with GraphQL
      # so skip the check entirely.
      unless graphql_request?
        # If an OAuth Application is using basic auth
        # return false even if the authentication was successful because
        # there isn't a `current_user`.
        return false if logged_in_as_oauth_application_via_basic_auth?
      end

      logged_in_as_user?
    end

    def logged_in_as_user?
      T.bind(self, AuthorizationTypes)

      !!current_user
    end

    def logged_in_as_key?
      !!authenticated_key
    end

    def logged_in_as_oauth_application_via_basic_auth?
      attempt_login_from_oauth_application
      @current_app_via_authorization_header.present?
    end

    # Public: Checks to see if the current request is truly anonymous or not
    def anonymous_request?
      !!(logged_in? || current_app.present?) ? false : true
    end

    def attempt_login_from_oauth_application
      # Do not set current_user to be nil
      # until we have confirmed that it is
      # an OAuth App using basic auth.
      login_from_oauth_application_credentials
    end

    def remote_token_auth?
      @remote_token_auth.present?
    end

    def attempt_remote_token_login(scope, forbid: false)
      T.bind(self, BaseAuthorizationTypes)

      if !logged_in?
        login_from_remote_token(scope, forbid: forbid)
      end

      if GitHub.private_mode_enabled? && @current_user.nil?
        if forbid
          deliver_error! 403, message: "Must authenticate to access this API."
        else
          deliver_error! 404
        end
      end
    end

    # Public: Tries to authenticate the user using on a Signed Auth Token, provided either using an "Authorization:
    # RemoteAuth" header or a query param.
    #
    # If the API method is only used internally, the `forbid` param can be set to true to provide more log
    # information. Otherwise we must return a 404 to prevent leaking information about the existence of a repository.
    #
    # If the login is successful, sets @current_user and @remote_token_auth.
    def login_from_remote_token(scope, forbid: false)
      T.bind(self, BaseAuthorizationTypes)

      token = Api::RequestCredentials.token_from_scheme(env, "remoteauth") || params[:token]

      if token && !token.to_s.dup.force_encoding("UTF-8").valid_encoding?
        if forbid
          deliver_error! 403, message: "Sorry, the provided token was unprocessable."
        else
          deliver_error! 404
        end
      end

      if token.present? && scope.present?
        @current_user = User.authenticate_with_signed_auth_token \
          token: token,
          scope: scope
        @remote_token_auth = !!@current_user.presence
      end
    end

    # Public: Fetches the OauthApplication for the current request.
    #
    # API clients can use basic auth with client_id:client_secret to receive a higher rate limit.
    #
    # May also return an `Integration` in `app/api/applications.rb`, see
    # https://github.com/github/github/blob/7830a583e23bbfa3ceb23251d4975639cbd018ca/app/api/applications.rb#L257-L268
    def current_app
      if @current_app.nil?
        @current_app = find_current_app || false
      end
      @current_app || nil
    end

    # Public: Fetches the Integration for the current request.
    def current_integration
      T.bind(self, AuthorizationTypes)

      return @current_integration if defined?(@current_integration)

      @current_integration = if logged_in? && current_user.is_a?(Bot)
        current_user.integration
      elsif integration_user_request?
        @oauth.application
      elsif current_app.is_a?(Integration)
        current_app
      else
        nil
      end
    end
    attr_writer :current_integration

    # Public: Fetches the ProgrammaticAccess for the current request.
    def current_programmatic_access
      T.bind(self, AuthorizationTypes)

      return @current_programmatic_access if defined?(@current_programmatic_access)
      @current_programmatic_access = current_user.present? ? current_user.programmatic_access : nil
    end

    # Public: Fetches the UserProgrammaticAccess for the current request.
    def current_user_programmatic_access
      return @current_user_programmatic_access if defined?(@current_user_programmatic_access)
      is_user_programmatic_access = current_programmatic_access.present? &&
                                    ProgrammaticAccess.user_type?(current_programmatic_access)
      @current_user_programmatic_access = is_user_programmatic_access ? current_programmatic_access : nil
    end

    # Internal: is the request by a user logged in with Oauth,
    # via an Integration?
    #
    # Returns a boolean.
    def integration_user_request?
      logged_in? && @oauth && @oauth.integration_application_type?
    end

    # Internal: is the request by a user logged in with Oauth,
    # via an Integration that is installed globally?
    #
    # Returns a boolean.
    def global_integration_user_request?
      return false unless integration_user_request?
      Apps::Internal.capable?(:installed_globally, app: @oauth.application)
    end

    # Internal: is the request by an Integration Bot?
    #
    # Returns a boolean.
    def integration_bot_request?
      T.bind(self, AuthorizationTypes)

      current_integration && current_user.is_a?(Bot)
    end

    # Internal: is the request by a UserProgrammaticAccess? aka PAT V2
    #
    # Returns a boolean.
    def user_programmatic_access_request?
      current_user_programmatic_access.present?
    end

    # Internal: is the request by a User, authenticated or not?
    #
    # Returns a boolean.
    def user_request?
      T.bind(self, AuthorizationTypes)

      current_user.is_a?(User) || current_user.nil?
    end

    # Public: Fetches the integration installation for the current request.
    #
    # Returns a IntegrationInstallation, (SiteScoped|Scoped)IntegrationInstallation, or nil.
    # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
    def current_integration_installation
      T.bind(self, AuthorizationTypes)

      @current_integration_installation ||= case
      when integration_bot_request?
        current_user.installation
      when integration_user_request?
        @oauth.installation
      end
    end
    # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

    # Public: Fetches the parent integration installation for the current request.
    #
    # Returns an IntegrationInstallation or nil.
    # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
    def current_parent_integration_installation
      @current_parent_integration_installation ||= case current_integration_installation
      when ScopedIntegrationInstallation
        current_integration_installation.parent
      end
    end
    # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

    # Public: Fetches the actor for the current request.
    #
    # Returns either a IntegrationInstallation, Integration, User, or nil.
    def current_actor
      T.bind(self, AuthorizationTypes)

      return current_integration_installation if current_integration_installation
      return current_user if current_user
      return current_app.owner if current_app
      return current_integration if current_integration
      nil # anonymous
    end

    # Public: The API should challenge anonymous requests with a 401 to
    # authenticate.  This is proper HTTP convention, but is disabled by default
    # so we don't leak private repositories.  Appropriate in other cases such as
    # "/user", or cases where a user has pull but not admin access and is trying
    # to access "/repos/:owner/:repo/hooks".
    #
    # Returns false.
    def challenge_api!
      T.bind(self, BaseAuthorizationTypes)

      env[ApiChallenge] = true
      false
    end

    # Internal: Indicates whether the API will respond with a 403 if authorization
    # fails. A 403 is proper HTTP convention for requests that fail authorization,
    # but we respond with 404 by default so that we don't leak private
    # repositories. A 403 is appropriate in other cases such as "/user", or cases
    # where a user has pull but not admin access and is trying to access
    # "/repos/:owner/:repo/hooks" (for example).
    #
    # Returns a String or nil. If the API will respond with a 403 for failed
    #   authorization, this method returns the message that will be included in
    #   the response. If the API will respond with a 404 for failed authorization,
    #   this method returns a falsely value.
    def forbidden_message
      T.bind(self, BaseAuthorizationTypes)

      env[ApiForbid]
    end

    # Public: Sets a 403 Forbidden message for requests that fail authorization.
    # This is proper HTTP convention, but is disabled by default so we don't leak
    # private repositories.  Appropriate in other cases such as "/user", or cases
    # where a user has pull but not admin access and is trying to access
    # "/repos/:owner/:repo/hooks".
    #
    # message   - String message to return in the API.
    # challenge - Boolean that tells the endpoint to challenge anonymous requests.
    #             Default: false.  See #challenge_api!
    # saml_error - Boolean that tells if the error came from a saml issue or not.
    #             Default: false
    #
    # Returns false.
    def set_forbidden_message(message, challenge = false, saml_error: false)
      if graphql_request?
        T.bind(self, AuthorizationTypes)
        raise Platform::Errors::Forbidden.new(message, extensions: { saml_failure: saml_error }) if @raise_on_error
      else
        T.bind(self, BaseAuthorizationTypes)
        env[ApiForbid] = message
        challenge_api! if challenge
        false
      end
    end

    # Public: Sets a 404 Not Found message for requests that fail authorization.
    # This is proper HTTP convention, but is disabled by default so we don't leak
    # resources form EMUs.
    #
    # Returns deliver_error! with a 404, or Platform::Errors::NotFound for graphQL
    def send_not_found
      if graphql_request?
        T.bind(self, AuthorizationTypes)
        raise Platform::Errors::NotFound.new("Not Found") if @raise_on_error
      else
        T.bind(self, BaseAuthorizationTypes)
        deliver_error!(404, message: "Not Found")
      end
    end

    # For users who belong to SAML-protected organizations, we may sometimes
    # serve them partial results when they make API requests. A partial result
    # set would indicate the user has one or more organizations that they need
    # to whitelist their OAuth token to access.
    def set_sso_partial_results_header(org_ids)
      T.bind(self, AuthorizationTypes)

      ids = org_ids.join(",")
      response.headers["X-GitHub-SSO"] = "partial-results; organizations=#{ids}"
    end

    # Halts with a 401 if the request is not authorized, there is not logged_in
    # user and the flag 'github.challenge' is set in the env Hash.
    #
    # Halts with a 403 if 'github.forbid' is set using the value as the message
    # returned to the user.
    #
    # Halts with a 404 if the request is not authorized.
    def deliver_authorization_error!
      T.bind(self, BaseAuthorizationTypes)

      if env[ApiChallenge] && !logged_in?
        deliver_error!(401)
      elsif message = forbidden_message
        deliver_error!(403, message: message)
      else
        deliver_error!(404)
      end
    end

    if !Rails.env.test?
      # Public: Checks the given block to see if the request is authorized.
      #
      # Yields nil in a block to check for authorization in a method.
      # Halts via #deliver_authorization_error! rules.
      #
      # Returns nothing.
      def check_authorization(&block)
        return if auth_is_valid?(&block)

        deliver_authorization_error!
      end
    else
      # Public: Checks the given block to see if the request is authorized.  This
      # is a special method in test mode so that certain tests can check
      # authorization very quickly.
      #
      # Yields nil in a block to check for authorization in a method.
      #
      # Halts with a 304 if the request is authorized and a test is checking
      #   authorization, otherwise halts according to #deliver_authorization_error! rules.
      #
      # Returns nothing.
      def check_authorization(&block)
        T.bind(self, BaseAuthorizationTypes)

        return if graphql_request?
        if auth_is_valid?(&block)
          env["github.authcheck"] && deliver_error!(304, message: "Authorization successful in test. See #{__FILE__}:#{__LINE__} for explanation")
        else
          deliver_authorization_error!
        end
      end
    end

    # Public: Check this app's AccessControl class if the current user has
    # access to the given verb.  This basically wraps #access_allowed? (which
    # may have a unique implementation per app) inside a #check_authorization
    # block.
    #
    # *args - Array of arguments to pass to #access_allowed?.
    #
    # Returns nothing.
    def control_access(*args)
      GitHub.tracer.in_span("#{self.class.name}##{__method__}", kind: :internal) do |_span|
        check_authorization { T.unsafe(self).access_allowed?(*args) }
      end
    end

    # Public: Scope checker shortcut for the protected resource.
    #
    # userish - An object that responds to #scopes.
    # scope   - The String scope to check against the scopes on userish.
    # options - The Hash of additional options for scope checking (optional).
    #           :target    - An object that responds to :method. Implies that your
    #                        userish object responds to the methods you've
    #                        defined on your whitelist.
    #           :method    - The method that returns the FixNum to be checked
    #                        against the whitelist. Defaults to :id.
    #           :whitelist - The Symbol name of a whitelist you've defined for
    #                        this scope.
    #
    # Returns truthy if this user has the specified scope.
    def scope?(userish, scope, options = nil)
      Api::AccessControl.scope?(userish, scope, options)
    end

    # Public: Set forbidden message unless the specified scope is given.
    #
    # scope   - String scope to check for.
    # options - Hash of options passed on to #scope? (optional).
    #           :message - String custom forbidden message.
    #
    # Returns nothing.
    def forbid_unless_scope(scope, options = nil)
      T.bind(self, AuthorizationTypes)

      options ||= {}
      unless scope?(current_user, scope, options)
        set_forbidden_message(options[:message] || "#{scope} or greater scope required")
      end
    end

    # Public: Check if access to a resource is allowed.
    #
    # verb    - The verb Symbol specifying the action to take against a resource.
    # options - Options Hash
    #           :resource                 - Generally a Model instance like a User
    #                                       or Repository.
    #           :user                     - The User that is attempting to access
    #                                       the resource.
    #           :challenge                - Boolean flag. True if a 401 should be
    #                                       returned to the caller if !logged_in?.
    #           :forbid                   - Set a standard forbid message.
    #           :enforce_oauth_app_policy - Boolean indicating whether to enforce
    #                                       the organization's OAuth application
    #                                       policy, if applicable to this access
    #                                       check (optional) (default: true).
    #
    # Returns truthy if access is allowed.
    def access_allowed?(verb, options = {})
      T.bind(self, AuthorizationTypes)

      # Primarily for database filtering, we don't want to simply raise an error if a GitHub App
      # doesn't have access to a resource. In those cases, we'll just return with `false` and
      # let the resolver handle the next move.
      @raise_on_error = options.fetch(:raise_on_error, true)

      if current_repo_loaded? && current_repo&.advisory_workspace? && !verb_allowed_for_workspace_repos?(verb)
        repo = current_repo.parent_advisory&.repository || current_repo

        unless repo.feature_enabled?(:maintainer_love_advisory_workspaces_can_use_actions)
          return set_forbidden_message("This action is forbidden on workspace repositories.")
        end
      end

      # If we've been explicitly passed an organization, set @access_control_org
      # so we can check for possible SAML enforcement on it.
      @access_control_org = options[:organization] if options[:organization]

      # Only two policies (TenantVerification and EmuVisibility) needs to run before other authorization checks so that we 404
      # instead of 403 so as not to leak the existence of an EMU user/enterprise
      return false unless satisfies_cap_policies?(action: verb, options: options, policies: first_run_cap_policies, allow_nil_resource: true)

      context = Platform::Authorization::ProgrammaticAccessContext.new(
        request_authn_context: self,
        repo_nwo_from_path: repo_nwo_from_path,
        current_resource_owner: current_resource_org_or_biz_owner,
        access_allowed_options: options
      )
      result = authorize_programmatic_actor(verb, context)
      return false unless result.success?

      return false unless satisfies_cap_policies?(action: verb, options: options)

      enforce_oauth_app_policy = options.fetch(:enforce_oauth_app_policy, true)
      if enforce_oauth_app_policy && !meets_oauth_application_policy?
        org = current_resource_org_or_biz_owner || @access_control_org
        log_oap_restriction(oauth_app: current_app_via_oauth, org: org)
        message = oauth_policy_error_message(org)
        return set_forbidden_message(message)
      end

      return false unless organization_credential_authorized?(options)

      return false unless intel_ip_allowlist_fix(action: verb, options: options)

      # Originally the final check in this conditional block was simply `organization_credential_authorized?`
      # since we are returning false earlier if those conditions are not met, and gitauth requires a T/F response
      # an explicit True value is required here
      true
    end

    def first_run_cap_policies
      [:tenant_verification, :enterprise_access_verification, :emu_visibility]
    end

    # Deny access to fork when root repository owner IP allowlist condition not met
    # Temporary for Intel. See https://github.com/github/reponauts/issues/53.
    def intel_ip_allowlist_fix(action:, options:)
      T.bind(self, AuthorizationTypes)

      if current_repo_loaded? && (!options[:ip_restricted_private_fork].nil? || current_repo.ip_restricted_private_fork?)
        return false if enforce_conditional_access_policies(
          current_repo.network_owner,
          policies: [:ip_allowlist]
        ) != :ok
      end

      true
    end

    # logic to evaluate CAP policies with the resource of conditional access provided by access_allowed?
    # returns true if all CAP policies were met, false otherwise
    def satisfies_cap_policies?(options:, action:, policies: cap_enforcer.conditional_access_policies, allow_nil_resource: false)
      # because users could also be provided via options, we need
      # to make this available to CAP framework via the callback
      set_actor_for_conditional_access(options: options)
      return true if cap_opted_out?(options)

      begin
        rfca = resource_for_conditional_access(action: action, options: options, fallback_takes_priority: true, tfca_method: :target_for_conditional_access) do
          fallback_resource_for_conditional_access(options: options)
        end
      rescue Platform::Errors::InternalExecution => e
        # since there is no resource skip cap policy when explicitly states to do do
        # at this time only EMU visibility policy is executed and we cannot determine if the resource is EMU-owned
        return true if allow_nil_resource && e.inner_error.is_a?(::ConditionalAccess::Enforcer::NilResourceError)
        raise Platform::Errors::InternalExecution, e.inner_error
      end

      policies_to_evaluate = policies - bypassed_policies(options)

      result = enforce_conditional_access_policies(rfca, policies: policies_to_evaluate)
      result == :ok
    end

    # defines a fallback strategy to obtain the resource for conditional access
    #
    # Moving forward, the canonical way to obtain the resource for conditional access
    # is the :resource argument, and every access_allowed? callsite should provide it
    # Updating all callsites would require some time, so instead we make this process
    # incremental by falling back to the "traditional" strategy, which relies on several
    # other arguments (:current_org, :organization, :repository, :repo)
    #
    # The :tfca argument provides a means to have callsites inject the
    # target for conditional access of the resource in a way that it does not
    # cause Platform::Errors::AssociationRefused
    def fallback_resource_for_conditional_access(options:)
      T.bind(self, AuthorizationTypes)

      fallback_tfca = target_for_conditional_access(options: options)
      return fallback_tfca if fallback_tfca.present? && fallback_tfca != :no_resource_for_conditional_access

      # hook so that TFCA can be loaded through a Promise without causing an N+1
      tfca = options[:tfca]
      return tfca if tfca.present?

      find_repo
    end

    # callers may disable conditional access
    # this should only be used when conditional access already took place somewhere else
    #
    # what led to this was GitAuth::Authorization::AccessControl#repository_accessible?
    # and to avoid making GitAuth check CAP two times, but also not being able
    # to provide the right return error
    def cap_opted_out?(options)
      options.fetch(:disable_conditional_access_policies, false)
    end

    def bypassed_policies(options)
      options.fetch(:bypass_cap_policies, [])
    end

    def authorize_programmatic_actor(verb, context)
      T.bind(self, AuthorizationTypes)

      authorizer = Platform::Authorization::ProgrammaticAccessAuthorizer.new(context)
      result = authorizer.authorize(verb, context.access_allowed_options)
      if GitHub.flipper[:platform_authorization_log_authz_decision].enabled? && result.failed?
        message = {
          "message" => "platform_auth.access_allowed",
          "gh.platform_auth.access_allowed.result" => "failed",
          "gh.platform_auth.access_allowed.authz_steps" => GitHub::JSON.encode(result.steps),
          "gh.request_id" => GitHub.context[:request_id],
        }
        GitHub.logger.info(message)
      end
      result
    end

    def oauth_policy_error_message(org)
      if org.nil? || org.user?
        # in the case of forked repos we may be receiving users in place of orgs
        # https://github.com/github/ecosystem-api/issues/4707
        <<~MSG.squish
        Although you appear to have the correct authorization credentials,
        this data is subject to OAuth App access restrictions, meaning that
        access to third-parties is limited. For more information on these restrictions, including
        how to enable this app, visit
        #{GitHub.help_url}/articles/restricting-access-to-your-organization-s-data/
        MSG
      elsif current_app_via_oauth&.blockable_client_app? && org.first_party_oauth_app_controls_feature_enabled?
        <<~MSG.squish
        Although you appear to have the correct authorization credentials,
        the `#{org.display_login}` organization has blocked access by this application.
        For more information on these restrictions, visit
        #{GitHub.help_url}/articles/restricting-access-to-your-organization-s-data/
        MSG
      else
        <<~MSG.squish
        Although you appear to have the correct authorization credentials,
        the `#{org.display_login}` organization has enabled OAuth App access restrictions, meaning that data
        access to third-parties is limited. For more information on these restrictions, including
        how to enable this app, visit
        #{GitHub.help_url}/articles/restricting-access-to-your-organization-s-data/
        MSG
      end
    end

    def cap_enforcer
      @conditional_access_enforcer ||= ConditionalAccess::Api::Public::Enforcer.new(self)
    end

    def cap_filter
      @conditional_access_filter ||= ConditionalAccess::Api::Public::Filter.new(self)
    end

    def target_for_conditional_access(options: {})
      T.bind(self, AuthorizationTypes)

      business = options[:resource] if [Platform::Models::Enterprise, Business].include?(options[:resource].class)

      # PublicResource can contain an actual resource get it
      public_resource = options[:resource] if options[:resource].is_a?(Platform::PublicResource)
      resource_from_public_resource = public_resource.resource if public_resource&.resource.present?

      @target_for_conditional_access = \
        business ||
        current_resource_org_or_biz_owner ||
        @access_control_org ||
        resource_from_public_resource ||
        public_resource || # this can return :no_target_for_conditional_access
        :no_resource_for_conditional_access
    end

    def actor_for_conditional_access
      @actor_for_conditional_access
    end

    def set_actor_for_conditional_access(options: {})
      @actor_for_conditional_access = options[:user] || current_actor
    end

    def web_session
      # This is set in app/platform/authorization/permission_check.rb
      # It is used as part of enforcing the optional SAML policy in packages/app_security/app/models/conditional_access/api/public/enforcer.rb
      @user_session
    end

    # This line is extracted into a method so that it can be overridden and cached by GraphQL requests
    # - resource: The resource we want to enforce access to. It must respond to :target_for_conditional_access
    # - fn: String representing the REST resource#verb or GraphQL schema for the current request.
    #       It is used when logging unauthorized requests
    # - policies: Optional Array of policies to enforce. Defaults to all policies registered with cap_enforcer.
    def enforce_conditional_access_policies(resource, policies: cap_enforcer.conditional_access_policies)
      cap_enforcer.enforce_conditional_access_policies(resource, policies: policies)
    end

    # Is the IP allow list conditional access policy enforceable?
    #
    # Returns Symbol.
    def ip_allowlist_enforceable
      GitHub.ip_allowlists_available? ? :yes : :no
    end

    # Allowed actions on a workspace repo are whitelisted to a small group of
    # required actions. cc https://github.com/github/pe-repos/issues/91
    #
    # New verbs should not be added to this list unless necessary for workspace workflows!
    # If you have questions, ask in #reponauts or ping @github/reponauts.
    ALLOWED_WORKSPACE_MUTATION_VERBS = [
      :create_commit_comment_reaction,
      :create_discussion_comment_reaction,
      :create_issue_related_reaction,
      :create_pull_request,
      :create_pull_request_comment,
      :create_pull_request_review_comment_reaction,
      :create_team_discussion_related_reaction,
      :delete_issue_comment,
      :delete_pull_request_review,
      :delete_pull_request_comment,
      :delete_reaction,
      :dismiss_pull_request_review,
      :edit_issue,
      :close_issue,
      :lock_issue,
      :mark_pull_request_ready_for_review,
      :minimize_repo_comment,
      :request_pull_request_review,
      :resolve_pull_request_review_thread,
      :submit_pull_request_review,
      :unlock_issue,
      :update_issue_comment,
      :close_pull_request,
      :update_pull_request,
      :update_pull_request_comment,
      :write_deployment,
      :write_deployment_status,
      :delete_deployment,
    ]

    def verb_allowed_for_workspace_repos?(verb)
      # All non mutation verbs are allowed
      return true unless @mutation

      ALLOWED_WORKSPACE_MUTATION_VERBS.include?(verb)
    end

    # This is extracted so that we can override it in GraphQL to use a cache,
    # that way we don't make these same DB calls over and over when we don't need to.
    def saml_enforced?(org, current_user)
      # this might load `Organization#business` to check SAML enforcement
      # there isn't a good way to make this async - ignore the association load
      Platform::LoaderTracker.ignore_association_loads do # rubocop:disable GitHub/IgnoreAssociationLoads
        saml_enforcement_policy = Organization::SamlEnforcementPolicy.new(organization: org, user: current_user)
        saml_enforcement_policy.enforced?
      end
    end

    # This is extracted so that we can override it in GraphQL to use a cache,
    # that way we don't make these same DB calls over and over when we don't need to.
    def get_credential_authorization(resource, org, oauth)
      # Log if we are getting different results for the Feature Flag, could do for experiment?
      if org&.business&.feature_enabled?(:saml_scope_private_resources_to_org)
        Organization::CredentialAuthorization.by_resource(resource: resource, credential: oauth, repo: @current_repo, org: org).first
      elsif org&.business&.feature_enabled?(:saml_scope_private_resources_to_org_experiment)
        run_saml_scope_experiment(resource, org, oauth)
      else
        Organization::CredentialAuthorization.by_repository(credential: oauth, repo: @current_repo, org: org).first
      end
    end

    # This is a temporary method to run the experiment for fixing a bug for SAML authorized access tokens
    # Issue: https://github.com/github/authorization/issues/3437
    # The proposed changes can break workflows of customers who are relying on the current behaviour
    # where a token for SAML-org-A can access private resources of SAML-org-B if they are in the same enterprise
    #
    # We are using a Feature Flag to control the experiment because we want finer control over the rollout and send mismatches to Splunk
    # The experiment is expected to return missmatches, to allow us identify how ofthen the new behaviour would
    # break user experience and give users via the audit-log the ability to self-audit and update their access tokens
    def run_saml_scope_experiment(resource, org, oauth)
      # Using match to send mismatch logs
      match = T.let(true, T::Boolean)
      control = Organization::CredentialAuthorization.by_repository(credential: oauth, repo: @current_repo, org: org)

      # return early if the request doesn't match experiment expectations
      return control.first unless org.present? && org.business.present? && (org.saml_sso_enabled? || org.business.saml_sso_enabled?)

      candidate = Organization::CredentialAuthorization.by_resource(resource: resource, credential: oauth, repo: @current_repo, org: org).first

      match = control.empty? ? candidate.nil? : control.include?(candidate)
      unless match
        GitHub.logger.info(
          "SAML Scope experiment mismatch",
          "code.namespace" => "Platform::Authorization",
          "code.function" => "get_credential_authorization_experiment",
          "gh.request_id" => GitHub.context[:request_id],
          "gh.business.id" => org&.business&.id,
          "gh.business.name" => org&.business&.slug,
          "gh.organization.id" => org&.id,
          "gh.organization" => org&.display_login,
          "gh.repository.id" => @current_repo&.id,
          "gh.oauth_access.id" => oauth&.id,
          "gh.oauth_application.type" => oauth&.application_type,
          "gh.external_identities.resource_type" => resource.class.name,
          "gh.saml_credential.experiment.controls" => control.as_json(only: [:id, :organization_id, :credential_id, :credential_type, :actor_id, :actor_type]),
          "gh.saml_credential.experiment.candidate" => candidate&.as_json(only: [:id, :organization_id, :credential_id, :credential_type, :actor_id, :actor_type]) || "nil",
        )
      end
      control.first
    end

    def request_hmac
      T.bind(self, T.any(BaseAuthorizationTypes, TwirpAuthorizationType))

      request&.env["HTTP_REQUEST_HMAC"]
    end

    def request_client_ip
      T.bind(self, T.any(BaseAuthorizationTypes, TwirpAuthorizationType))

      request&.env["HTTP_X_CLIENT_IP"]
    end

    def request_forwarded_for
      T.bind(self, T.any(BaseAuthorizationTypes, TwirpAuthorizationType))

      request&.env["HTTP_X_FORWARDED_FOR"]
    end

    # These are the HMAC keys of internal services that use our internal API
    # and require that end-user IPs be used for IP allow list checks instead of
    # the IPs of the service itself.
    def internal_service_hmac_keys_for_ip_allowed_check
      [
        GitHub.api_internal_package_registry_hmac_keys,
        GitHub.api_internal_lfs_hmac_keys,
        GitHub.api_internal_raw_hmac_keys,
        GitHub.api_internal_archive_hmac_keys,
        GitHub.internal_api_hmac_key
      ].flatten
    end

    def ip_for_allowed_check
      T.bind(self, AuthorizationTypes)

      return @ip_for_allowed_check if defined?(@ip_for_allowed_check)

      # Use X-Client-IP header value if request is on behalf of a trusted internal
      # service that proxies end-user requests.
      if request_hmac.present?
        hmac_status, matching_key = GitHub::RequestHmacValidator.verify_request_hmac(
          request_hmac, internal_service_hmac_keys_for_ip_allowed_check
        )

        if matching_key.present? && request_client_ip.present? && hmac_status == :success
          return @ip_for_allowed_check = request_client_ip
        end
      end

      @ip_for_allowed_check = remote_ip
    end

    def request_from_internal_ip?(ip)
      return false if GitHub.enterprise?
      [
        "10.0.0.0/8"
      ].each do |cidr|
        range = IPAddr.new(cidr)
        return true if range.include?(ip)
      end
      false
    end

    def request_forwarded_for_client_ip
      return unless request_forwarded_for.present?
      request_forwarded_for.split(",").first.strip
    end

    def ip_allow_list_exempt_internal_api_request?
      return false if !GitHub.internal_api_role?

      # Check if actor is exempt from IP allow list enforcement on requests from
      # internal services to internal-api hosts.

      # Currently limited to group-syncer and requests from capable Apps.
      group_syncer_request? || Apps::Internal.capable?(:ip_allowlist_exempt_for_internal_apis, app: current_integration)
    end

    def group_syncer_request?
      current_integration&.group_syncer_github_app?
    end

    def connect_request?
      current_integration&.connect_app?
    end

    def organization_credential_authorized?(options)
      T.bind(self, AuthorizationTypes)

      return true if GitHub.global_business&.enterprise_server_scim_enabled?
      return true if @remote_token_auth && logged_in?
      return true if integration_bot_request?
      return true if user_programmatic_access_request?
      return true unless owner = current_resource_org_or_biz_owner || @access_control_org
      return true unless owner.organization?
      return true unless saml_enforced?(owner, current_user)

      # If we fail, we'll start building out the X-GitHub-SSO header. It may
      # stay like this or it may contain a URL to authorize an OAuth token.
      sso_header = "required"
      message = "Resource protected by organization SAML enforcement."

      if @oauth
        return true unless @oauth.saml_enforceable?

        resource = options[:resource] || @current_repo
        credential = get_credential_authorization(resource, owner, @oauth)

        if credential
          # If we have a whitelisted OAuth token, we're good.
          return true if credential.active?

          # Otherwise, access has been revoked. Let the user know.
          if @current_repo&.internal?
            message = "#{message} Your token's access was revoked. Please generate a new #{token_type_for(@oauth)} token and grant it access to an organization within this enterprise."
          else
            message = "#{message} Your token's access was revoked. Please generate a new #{token_type_for(@oauth)} token and grant it access to this organization."
          end
        else
          # An OAuth token is being used but has not ever been authorized, so
          # generate a new authorization request for the user in the SSO header.
          if @current_repo&.internal?
            message = "#{message} You must grant your #{token_type_for(@oauth)} token access to an organization within this enterprise."
          else
            message = "#{message} You must grant your #{token_type_for(@oauth)} token access to this organization."
          end

          url = authorize_path(owner)
          sso_header = "#{sso_header}; url=#{url}"
        end
      elsif options[:user_session].present? && !!options[:authenticated_actor_using_web_session]
        resource_for_cap = @current_repo || owner
        results = enforce_conditional_access_policies(resource_for_cap, policies: [:saml])

        return results == :ok
      else
        # No OAuth token was used.
        if @current_repo&.internal?
          message = "#{message} Use a Personal Access Token (PAT) or OAuth Token that has been granted access to an organization within this enterprise."
        else
          message = "#{message} Use a Personal Access Token (PAT) or OAuth Token that has been granted access to this organization."
        end
      end

      @documentation_url = GitHub.sso_credential_authorization_help_url
      response.headers["X-GitHub-SSO"] = sso_header if response
      set_forbidden_message(message, saml_error: true)

      false
    end

    # Public: Gets an AccessGrant for a resource.
    #
    # verb    - The verb Symbol specifying the action to take against a resource.
    # options - Options Hash
    #           :resource  - Generally a Model instance like a User or Repository.
    #           :user      - The User that is attempting to access the resource.
    #           :challenge - Boolean flag. True if a 401 should be returned to
    #                        the caller if !logged_in?.
    #           :forbid    - Set a standard forbid message.
    #           :forbid_message - A message to use if `forbid` is true and authorization fails
    #           ...
    #
    # Returns an Egress:AccessGrant object
    def access_grant(verb, options = nil)
      T.bind(self, AuthorizationTypes)

      options ||= {}

      challenge_api! if options[:challenge]

      if options[:forbid]
        default_forbidden_message = "Must have admin rights to Repository."
        message = forbidden_message || options[:forbid_message] || default_forbidden_message
        set_forbidden_message(message)
      end

      options[:verb] = verb
      options[:user] ||= current_user
      options[:public_key] ||= @authenticated_key
      options[:integration] ||= current_integration

      resource = options[:resource]

      grant = Api::AccessControl.access_grant(options)
      @accepted_scopes ||= grant.accepted_scopes
      grant
    end

    # Public: Checks to see if the current User has the proper OAuth scope to
    # access the given Repository.
    #
    # repo - Repository instance.
    #
    # Returns true if the User has the right scopes, otherwise false.
    def oauth_allows_access?(repo)
      T.bind(self, AuthorizationTypes)

      Api::AccessControl.oauth_allows_access?(current_user, repo)
    end

    # Public: Checks if the current request is a GraphQL request
    #
    # Returns boolean
    def graphql_request?
      defined?(@graphql_request) && @graphql_request
    end

    # Public: Logs information when an app is restricted by an Organization's OAuth App Policy
    #
    # Returns boolean
    def log_oap_restriction(oauth_app:, org:)
      return unless oauth_app.present? && org.present?

      if GitHub.flipper[:log_api_oap_restrictions].enabled?
        log_info = {
          "gh.app_id" => oauth_app.id,
          "gh.request_id" => GitHub.context[:request_id],
          "http.route" => GitHub.context[:api_route]
        }

        if org.organization?
          is_blocked = oauth_app.blockable_client_app? && org.first_party_oauth_app_restrictions_enabled?
          log_info.merge!({
            target_org_id: org.id,
            restriction_type: is_blocked ? "blocked" : "unapproved"
          })
        else
          # in the case of forked repos we may be receiving users in place of orgs
          # https://github.com/github/ecosystem-api/issues/4707
          log_info.merge!({ "gh.target_user_id" => org.id })
        end
        GitHub.logger.info(
          "OAuth app API request restricted by org OAP.",
          log_info
        )
      end
    end

    private

    def authorize_path(owner)
      T.bind(self, AuthorizationTypes)

      target = owner.external_identity_session_owner

      token = ::Organization::CredentialAuthorization.generate_request \
        organization: owner, target: target, credential: @oauth, actor: current_user

      case target
      when ::Organization
        Api::Serializer.html_url("/orgs/#{target.display_login}/sso", authorization_request: token)
      when ::Business
        Api::Serializer.html_url("/enterprises/#{target}/sso", authorization_request: token)
      end
    end

    # Private: Get enterprise managed business from the actor
    #
    # item - item can be a user/org/business. Returns the emu business of any item
    # Return nil if actor is not enterprise managed.
    #
    def fetch_enterprise_managed_business_for(item)
      case item
      when Organization
        return item.business if item.async_enterprise_managed_user_enabled?.sync
      when Business
        return item if item.enterprise_managed_user_enabled?
      when User
        return item.enterprise_managed_business if item.is_enterprise_managed?
      else
        # we should not reach here. If we do, log and do nothing
        GitHub.logger.info("#{item.class.name} is not an org, biz or user.", "code.function" => "fetch_enterprise_managed_business_for")
      end
    end

    def login_from_oauth_application_credentials
      T.bind(self, BaseAuthorizationTypes)

      return @current_app_via_authorization_header if defined?(@current_app_via_authorization_header)

      @current_app_via_authorization_header = nil

      return unless request_credentials.login_password_present?

      # login is ok in lookups
      if (app = OauthApplication.find_by_key(request_credentials.login)) # rubocop:disable GitHub/DoNotAllowLogin
        @current_user = nil

        # login is ok in lookups
        if !current_app_from_client_parameters(request_credentials.login, request_credentials.password) # rubocop:disable GitHub/DoNotAllowLogin
          reject_for_bad_credentials!
        elsif app.suspended?
          reject_for_suspended_oauth_application!
        else
          @current_app = @current_app_via_authorization_header = app
        end
      end
    end

    # Determine whether the request should result in a two-factor OTP SMS being sent.
    def request_sends_otp_sms?
      route_sends_otp_sms? && otp_header_unset?
    end

    # Determines whether the current route supports delivery of a one-time password
    # via SMS.
    #
    # This method should be overridden in classes that require SMS to be sent.
    #
    # Returns false.
    def route_sends_otp_sms?
      false
    end

    def otp_header_unset?
      T.bind(self, BaseAuthorizationTypes)

      !request.env.key?("HTTP_X_GITHUB_OTP")
    end

    # Internal: Finds the OauthApplication (if any) associated with the current
    # request.
    #
    # Returns an OauthApplication or nil.
    def find_current_app
      current_app_via_oauth
    end

    # Internal: Finds the OauthApplication associated with the OauthAccess (if
    # any) used to authenticated the current request.
    #
    # Returns an OauthApplication or nil.
    def current_app_via_oauth
      if @oauth && @oauth.oauth_application_type?
        @oauth.async_application.sync
      end
    end

    # Internal: Finds the OauthApplication (if any) that matches the client ID
    # and client secret passed via an authorization header.
    #
    # Returns an OauthApplication or nil.
    def current_app_via_authorization_header
      # login is ok in lookups
      current_app_from_client_parameters(request_credentials.login, request_credentials.password) # rubocop:disable GitHub/DoNotAllowLogin
    end

    # Internal: Finds the Integration (if any) that matches the client ID
    # and client secret passed via an authorization header.
    #
    # Returns an Integration or nil.
    def current_integration_via_authorization_header
      # login is ok in lookups
      current_integration_from_client_parameters(request_credentials.login, request_credentials.password) # rubocop:disable GitHub/DoNotAllowLogin
    end

    def current_app_from_client_parameters(client_id, client_secret)
      return nil if client_id.blank? || client_secret.blank?
      hash = OauthApplicationClientSecret.hash_for(client_secret)
      oauth_app_client_secret = OauthApplicationClientSecret.joins(:oauth_application).where(secret_hash: hash).where("oauth_applications.key" => client_id).first

      return unless oauth_app_client_secret
      return unless oauth_application = oauth_app_client_secret.oauth_application

      oauth_app_client_secret.access

      oauth_application
    end

    def current_integration_from_client_parameters(client_id, client_secret)
      return nil if client_id.blank? || client_secret.blank?

      hash = IntegrationClientSecret.hash_for(client_secret)
      integration_client_secret = IntegrationClientSecret.joins(:integration).where(secret_hash: hash).where("integrations.key" => client_id).first

      return unless integration_client_secret
      return unless integration = integration_client_secret.integration

      integration_client_secret.access

      integration
    end

    def require_api_semantic_version(semantic_version)
      T.bind(self, BaseAuthorizationTypes)

      deliver_error! 404 unless medias.semantic_version?(semantic_version)
    end

    def request_credentials
      exec_context.request_credentials
    end

    # Checks the block for authorization.
    # Yields nil in a block to check for authorization in a method.
    def auth_is_valid?(&block)
      !block || block.call
    end

    # Private: Determines whether the request satisfies the OAuth application
    # policy associated with the resources being accessed by the request.
    #
    # Returns true if the request satisfies the OAuth application policy or if no
    #   OAuth application policy applies to this request. Otherwise, returns
    #   false.
    def meets_oauth_application_policy?
      meets_oauth_application_policy_for_this_org? &&
        meets_oauth_application_policy_for_this_repo?
    end

    # Private: If the request involves a specific organization's resources,
    # determine whether the request satisfies the organization's OAuth application
    # policy.
    #
    # Returns false when *all* of the following conditions exist:
    #   - the request involves a single organization's resources, and
    #   - the request is from an OAuth application, and
    #   - the application violates the organization's OAuth application policy
    #
    #   Otherwise, returns true.
    def meets_oauth_application_policy_for_this_org?
      T.bind(self, AuthorizationTypes)

      return true unless requestor_governed_by_oauth_application_policy?

      org = find_org
      return true unless org

      org.allows_oauth_application?(current_app_via_oauth)
    end

    # Private: If the request involves a specific repository, determine whether
    # the request satisfies the repository's OAuth application policy.
    #
    # Returns false when *all* of the following conditions exist:
    #   - the request involves a single repository, and
    #   - the request is from an OAuth application, and
    #   - the application violates the repository's OAuth application policy, and
    #   - the request is performing a non-read-only operation related to a public
    #     repository, or any kind of operation related to a private repository
    #
    #   Otherwise, returns true.
    def meets_oauth_application_policy_for_this_repo?
      T.bind(self, AuthorizationTypes)

      req = graphql_request? ? nil : T.unsafe(self).request
      OauthApplicationPolicy::HttpRequest.new(
        repository: find_repo,
        user: current_user,
        request: req,
      ).satisfied?
    end

    # Private: Determine whether OAuth application policies apply to the request.
    #
    # Returns a Boolean.
    def requestor_governed_by_oauth_application_policy?
      GitHub.oauth_application_policies_enabled? && current_app_via_oauth
    end

    def token_type_for(oauth_access)
      oauth_access.personal_access_token? ? "Personal Access" : "OAuth"
    end
  end
end
