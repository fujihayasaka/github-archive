# typed: true
# frozen_string_literal: true

module Platform
  module Authorization
    # A short-lived object that calls through to our API authorization code.
    # Isolate the parts of code that coordinate with the `Authorization` module.
    class PermissionCheck
      include Authorization
      include App::IExecContextAccessor

      # Setup the object with some state from the parent `Permission` instance.
      # This object can't be `freeze`d because `Authorization` caches some data in ivars.
      def initialize(current_user:, installation:, integration:, operation:, response:,
        oauth:, current_repo:, current_org:, mutation:, saml_enforced_cache:,
        credential_authorization_cache:, oauth_app_authorization_cache:, cap_resource_policy_cache:, resource: nil,
        remote_ip: nil, request_hmac: nil, request_client_ip: nil, raise_on_error: nil, authenticated_actor_using_web_session: false, user_session: nil,
        request_access_security_header: nil, request_forwarded_for: nil, query_name: nil)
        @current_user = current_user
        @installation = installation
        @integration = integration
        @operation = operation
        @resource = resource
        @response = response
        @graphql_request = true
        @oauth = oauth
        @current_repo = current_repo
        @current_org = current_org
        @mutation = mutation
        @saml_enforced_cache = saml_enforced_cache
        @credential_authorization_cache = credential_authorization_cache
        @oauth_app_authorization_cache = oauth_app_authorization_cache
        @cap_resource_policy_cache = cap_resource_policy_cache
        @remote_ip = remote_ip
        @request_hmac = request_hmac
        @request_client_ip = request_client_ip
        @request_forwarded_for = request_forwarded_for
        @query_name = query_name

        # Usually, this is set in `Platform::Authorization#access_allowed?`, but that creates
        # a sequenece dependency for `#organization_credential_authorized?`.
        #
        # So, accept an option here that will be used if `#access_allowed?` isn't called.
        @raise_on_error_gql = raise_on_error
        @authenticated_actor_using_web_session = authenticated_actor_using_web_session
        @user_session = user_session
        @request_access_security_header = request_access_security_header
      end

      # This overrides Authorization#access_allowed?;
      # set it up with some GraphQL-specific stuff.
      def access_allowed?(action, **options)
        # OAP should be enforced for mutations; unauthorized Oauth Apps can
        # query public resources but cannot mutate them
        # Exceptions should pass the `allow_mutation_on_public_resource` flag.
        if @operation == :mutation
          options[:enforce_oauth_app_policy] = enforce_oauth_app_policy_in_mutation?(options)
        else
          if options[:enforce_oauth_app_policy].nil?
            options[:enforce_oauth_app_policy] = @current_repo.nil? ? true : @current_repo.private?
          end
        end

        if @authenticated_actor_using_web_session
          options[:authenticated_actor_using_web_session] = true
          options[:user_session] = @user_session
        end

        if @current_org.present?
          @current_org.async_saml_provider.sync
        end

        if @installation.present?
          options[:installation] = @installation
        elsif @integration.present?
          options[:integration] = @integration
        end

        super
      end

      # These override methods in `Authorization` to short-circuit (or implement) data requirements.
      #
      # Actually, not all of them are overrides: some are just implicitly
      # required by the methods in `Authorization`.
      def current_resource_org_or_biz_owner
        @current_org
      end

      alias :find_org :current_resource_org_or_biz_owner

      attr_reader :current_repo, :current_user
      alias :find_repo :current_repo

      def current_repo_loaded?
        @current_repo.present?
      end

      attr_reader :response

      def read_request?
        @operation == :query
      end

      def graphql_request?
        true
      end

      def repo_nwo_from_path
        # nwo used for lookups and not customer facing
        current_repo_loaded? && current_repo.nwo # rubocop:disable GitHub/DoNotAllowNameWithOwner
      end

      def remote_ip
        @remote_ip
      end

      def request_hmac
        @request_hmac
      end

      def request_access_security_header
        @request_access_security_header
      end

      def request_client_ip
        @request_client_ip
      end

      def request_forwarded_for
        @request_forwarded_for
      end

      def params
        {}
      end

      # Internal: is the request by a user logged in with Oauth,
      # via an Integration?
      #
      # Returns a boolean.
      def integration_user_request?
        @current_user&.oauth_access&.integration_application_type?
      end

      # Internal: is the request by a user logged in with Oauth,
      # via an Integration installed globally?
      #
      # Returns a boolean.
      def global_integration_user_request?
        return false unless integration_user_request?
        Apps::Privileged.capable?(:installed_globally, app: @current_user.oauth_access.application)
      end

      # Override this to use the passed-in cache, which lasts for a whole GraphQL query
      def saml_enforced?(org, user)
        org_cache = @saml_enforced_cache[org]
        if org_cache.key?(user)
          org_cache[user]
        else
          org_cache[user] = super(org, user)
        end
      end

      # Override this to use the passed-in cache, which lasts for a whole GraphQL query
      def enforce_conditional_access_policies(resource, policies: cap_enforcer.conditional_access_policies, options: {}, preload_results: false)
        # cache is nested hash { policies => { resource => value }
        cache_val = @cap_resource_policy_cache[policies][resource]
        cache_hit = !cache_val.nil?
        if cache_hit
          @cap_resource_policy_cache[policies][resource]
        else
          @cap_resource_policy_cache[policies][resource] = super(resource, policies: policies, options:, preload_results:)
        end
      end

      # Override this to use the passed-in cache, which lasts for a whole GraphQL query
      def get_credential_authorization(resource, org, oauth)
        business_promise = org&.async_business || Promise.resolve(nil)

        business_promise.then do |business|
          visibility = get_cache_visibility_key(business, resource, org)
          org_cache = @credential_authorization_cache[org][visibility]
          if org_cache.key?(oauth)
            org_cache[oauth]
          else
            org_cache[oauth] = super(resource, org, oauth)
          end
        end.sync
      end

      # Override this to use the passed-in cache, which lasts for a whole GraphQL query
      def get_credential_authorization_repo_scoped(resource, org, oauth, repo)
        business_promise = org&.async_business || Promise.resolve(nil)
        repo_id = repo&.id || 0

        business_promise.then do |business|
          visibility = get_cache_visibility_key(business, resource, org, repo_id: repo_id)
          org_cache = @credential_authorization_cache[org][visibility]
          if org_cache.key?(oauth)
            org_cache[oauth]
          else
            org_cache[oauth] = super(resource, org, oauth, repo)
          end
        end.sync
      end

      # Override this to use the passed-in cache, which lasts for a whole GraphQL query
      def authzd_credential_passes_saml_enforcement?(resource, owner, oauth, repo_id)
        return super(resource, owner, oauth, repo_id) if oauth.nil?
        # :no_target_for_conditional_access
        return super(resource, owner, oauth, repo_id) if owner.is_a?(Symbol)
        business_promise = owner&.async_business || Promise.resolve(nil)

        business_promise.then do |business|
          visibility = "authzd_#{get_cache_visibility_key(business, resource, owner, repo_id: repo_id)}"
          org_cache = @credential_authorization_cache[owner][visibility]

          if org_cache.key?(oauth)
            org_cache[oauth]
          else
            org_cache[oauth] = super(resource, owner, oauth, repo_id)
          end
        end.sync
      end

      def get_cache_visibility_key(business, resource, org, repo_id: nil)
        visibility = "private"

        if !business.nil? && !FeatureFlag.vexi.enabled?(:saml_scope_private_resources_to_business, business, default: false)
          visibility = "internal" if Organization::CredentialAuthorization.is_resource_internal_or_public?(resource: resource, org: org)
        end

        if !repo_id.nil?
          visibility = "#{visibility}_#{repo_id}"
        end

        visibility
      end

      # Override this to use the passed-in cache, which lasts for a whole GraphQL query
      def meets_oauth_application_policy?
        org = find_org
        repo = find_repo

        # Don't cache if we don't have an org or repo
        return super unless org && repo

        cache = @oauth_app_authorization_cache[org][repo]

        if cache.key?(current_app_via_oauth)
          cache[current_app_via_oauth]
        else
          cache[current_app_via_oauth] = super
        end
      end

      # Is the IP allow list conditional access policy enforceable?
      #
      # Returns Symbol.
      def ip_allowlist_enforceable
        GitHub.ip_allowlists_available? ? :yes : :no
      end

      # Is the external conditional access policy enforceable?
      #
      # Returns Symbol.
      def external_conditional_access_policy_enforceable
        GitHub.idp_cap_available? ? :yes : :no
      end

      # Is the EMU Visibility conditional access policy enforceable?
      #
      # Returns Symbol.
      def emu_visibility_enforceable
        if read_request? && ::FeatureFlag.vexi.enabled_or_raise?(:skip_emu_visibility_cap_internal_apps, current_user) && # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
          @resource&.is_a?(Integration) && Apps::Privileged.capable?(:skip_emu_visibility_cap, app: @resource)
          # allow first-party apps with :skip_emu_visibility_cap (e.g. Actions) to be visible to EMUs in GraphQL
          return :no
        end

        :yes
      end

      # Is the EMU Ownership conditional access policy enforceable?
      #
      # Returns Symbol.
      def emu_ownership_enforceable
        if read_request? && @resource&.is_a?(Integration) && Apps::Privileged.capable?(:skip_emu_ownership_cap, app: @resource)
          # allow first-party apps with :skip_emu_ownership_cap (e.g. Actions) to be visible to EMUs in GraphQL
          return :no
        end

        if @current_repo&.public && @current_user&.is_enterprise_managed? && @query_name == "updateIssueSubscriptionMutation"          # allow EMUs to subscribe to public issues
          return :no
        end

        :yes
      end

      def enforce_oauth_app_policy_in_mutation?(options)
        allow_mutation_on_public_resource = options.fetch(:allow_mutation_on_public_resource, false)
        return true unless allow_mutation_on_public_resource

        current_repo_is_public = @current_repo&.public?
        resource_is_public_app = options[:resource].is_a?(Integration) && options[:resource].public_visibility?
        return true unless current_repo_is_public || resource_is_public_app

        false
      end

      sig { override.returns(App::IContext) }
      def exec_context
        raise Platform::Errors::NotImplemented, "#exec_context is not implemented on PermissionCheck"
      end
    end
  end
end
