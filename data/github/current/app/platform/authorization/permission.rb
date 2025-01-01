# typed: true
# frozen_string_literal: true

module Platform
  module Authorization
    class Permission
      include ::Platform::Authorization::ConditionalAccessDependency
      include Scientist

      extend T::Helpers
      extend T::Sig

      attr_reader :viewer, :scopes, :oauth_app, :response, :integration, :installation,
        :actor, :origin, :remote_ip, :cap_filter, :request_access_security_header

      # Truthy when evaluating permissions for a root-level mutation field.
      # Falsey when evaluating permissions for the inner selections of the mutation operation.
      attr_accessor :mutation

      attr_accessor :target

      # used in cases where a permission check is always visible
      ALWAYS_PUBLIC = true.freeze

      sig { params(context: T.any(Platform::IContext, GraphQL::Query::Context)).void }
      def initialize(context)
        @authenticated_actor_using_web_session = context[:authenticated_actor_using_web_session]
        @user_session = context[:user_session]
        @enforce_conditional_access_via_graphql = context[:enforce_conditional_access_via_graphql]
        @viewer = context[:viewer]
        @viewer_id = viewer.try(:id)
        @scopes = context[:granted_oauth_scopes] || nil
        @oauth_app = context[:oauth_app]
        @integration = context[:integration]
        @installation = context[:installation]
        @actor = context[:actor]
        @oauth = @viewer.try(:oauth_access)
        @origin = context[:origin]
        raise Platform::Errors::Internal, "origin must be defined" unless @origin.present?
        @target = context[:target]
        # Sometimes `context` is a GraphQL::Query::Context,
        # other times it's just a Hash.
        @operation = if context.respond_to?(:query)
          # Only use cast if the above responds_to? check is present
          T.cast(context, GraphQL::Query::Context).query.mutation? ? :mutation : :query
        else
          :query
        end
        # The Sinatra::Response object that's set--and used--by API calls
        @response = context[:response]
        @typed_can_see_cache = Hash.new { |h, k| h[k] = {} }
        @typed_api_can_access_cache = Hash.new { |h, k| h[k] = {} }

        # These are used to cache database lookups for some public API permission checks.
        # The REST API doesn't use caching because it usually only makes these checks once,
        # but in GraphQL, there's a check for each resource owner reflected in the response.
        #
        # Cache of `{ org => { user => boolean } }` for whether `@viewer` should undergo SAML enforcement for this `org`
        @saml_enforced_cache = Hash.new { |h, k| h[k] = {} }
        # { org => { oath => Organization::CredentialAuthorization } }
        @credential_authorization_cache = Hash.new { |h, k| h[k] = {} }
        # { org => { repo => { oauth_app =>  Boolean } }
        @oauth_app_authorization_cache = Hash.new { |h, org| h[org] = Hash.new { |hh, repo| hh[repo] = {} } }

        # Public requests go through the Platform::Authorization::PermissionCheck
        # and use the ConditionalAccess::Api::Public::Enforcer.
        # The Internal requests use the internal enforcer.
        # Both leverage the cache to amortize costs of evaluating resources belonging to the same organization.
        @cap_enforcer = ConditionalAccess::Api::Internal::Enforcer.new(context)
        @cap_resource_policy_cache = Hash.new { |h, k| h[k] = {} }

        # Public requests have a ConditionalAccess::API::Public::Filter,
        # whereas internal requests (which originate from Rails controllers), have a ConditionalAccess::Web::Filter.
        # Both filters have caching embedded into them.
        @cap_filter = context[:cap_filter]

        @remote_ip = context[:ip]
        @request_hmac = context[:request_hmac]
        @request_client_ip = context[:request_client_ip]
        @request_forwarded_for = context[:forwarded_for]

        @request_access_security_header = context[:request_access_security_header]
        @operation_id = context[:operation_id]
        @query_name = context[:query_name]
        @query_owning_catalog_service = context[:query_owning_catalog_service]
        @actor_limiter_cache = Hash.new { false }
        freeze
      end

      def typed_can_see?(type_name_or_class, object)
        if object.nil?
          # anyone can see `nil`
          return Promise.resolve(true)
        end

        case type_name_or_class
        when String
          type_name = type_name_or_class
          type_defn_class = begin
            Platform::Objects.const_get(type_name)
          rescue NameError
            raise Errors::Internal, <<~ERR
            Unexpected GraphQL type passed to `.typed_can_see?`: #{type_name.inspect}

            This method expects a GraphQL type name (eg `"Repository"`) or a GraphQL type definition class (eg `Platform::Objects::Repository`).

            For more help with this error, post a link to a CI failure in #graphql!
            ERR
          end
        when Class
          type_defn_class = type_name_or_class
          type_name = T.unsafe(type_defn_class).graphql_name
        else
          raise Errors::Internal, "Unexpected `.typed_can_see?` type: #{type_name_or_class.inspect} (#{type_name_or_class.class}), object class: #{object.class}"
        end

        @typed_can_see_cache[type_defn_class].fetch(object) do
          # rubocop:disable GitHub/GraphqlAuthorizationMethodsArentCalled
          # This is the one place that `.async_viewer_can_see?` is allowed
          # Call the last-ditch authorization hook on that object
          type_defn_response = type_defn_class.async_viewer_can_see?(self, object)
          # rubocop:enable GitHub/GraphqlAuthorizationMethodsArentCalled
          # And resolve the promise, if it returned one, returning a new promise
          promise = Promise.resolve(type_defn_response).then do |accessible|
            GitHub.dogstats.increment("platform.abilities.can_read", sample_rate: 0.001, tags: ["accessible:#{accessible}", "type_name:#{type_name}"])
            accessible
          end
          @typed_can_see_cache[type_defn_class][object] = promise
        end
      end

      def authorize_content(content_type, operation, data = {})
        authorization = ContentAuthorizer.authorize(@viewer, content_type, operation, data)
        if authorization.failed?
          raise Errors::Unprocessable.new(authorization.error_messages)
        end
      end

      def preload_spammable(object)
        if object.respond_to?(:user_association_for_spammy)
          Loaders::ActiveRecordAssociation.load(object, object.user_association_for_spammy)
        else
          Promise.resolve(nil)
        end
      end

      def spam_check(object, &block)
        preload_spammable(object).then do
          if object.respond_to?(:hide_from_user?) && object.hide_from_user?(viewer)
            false
          elsif block_given?
            yield object
          else
            true
          end
        end
      end

      def belongs_to_git_object(object)
        typed_can_see?("Repository", object.repository)
      end

      def belongs_to_issue(object)
        spam_check(object) do
          object.async_issue.then do |issue|
            next false if issue.nil?
            typed_can_see?("Issue", issue)
          end
        end
      end

      def belongs_to_project(object)
        object.async_project.then { |project| typed_can_see?("Project", project) }
      end

      def belongs_to_pull_request(object, pull_request = nil)
        spam_check(object) do
          promise = pull_request.present? ? Promise.resolve(pull_request) : object.async_pull_request
          promise.then do |pull_request|
            typed_can_see?("PullRequest", pull_request)
          end
        end
      end

      def belongs_to_repository(object)
        object.async_repository.then do |repository|
          typed_can_see?("Repository", repository)
        end
      end

      def belongs_to_collection(object)
        object.async_collection.then do |collection|
          typed_can_see?("ExploreCollection", collection)
        end
      end

      def belongs_to_viewer(object)
        viewer && object.user_id == viewer.id
      end

      def load_repo_and_owner(obj)
        obj.async_repository.then do |repo|
          repo.async_owner.then do |owner|
            repo.async_internal_repository.then do
              if owner.is_a?(Organization)
                repo.async_organization.then { repo }
              else
                repo
              end
            end
          end
        end
      end

      def async_repo_and_org_owner(obj)
        obj.async_repository.then do |repo|
          repo.async_owner.then do |owner|
            repo.async_internal_repository.then do
              if owner.is_a?(Organization)
                repo.async_organization.then { next repo, owner }
              else
                next repo, nil
              end
            end
          end
        end
      end

      def async_owner_if_org(obj)
        return nil unless obj
        if obj.is_a?(Platform::Models::RepositoryAdminInfo)
          obj = obj.repo
        end
        obj.async_owner.then do |owner|
          if owner.is_a?(Organization)
            owner
          end
        end
      end

      def authenticating_as_app?
        # Some Marketplace API endpoints are authenticated using app credentials
        # instead of user credentials.
        viewer.blank? && (oauth_app.present? || integration.present?)
      end

      if Rails.env.test?
        # In test, we can call stuff on `permission` without query scope
        # so allow it to fallback to this
        def associated_repository_ids(repository_ids: nil)
          Platform::Security::RepositoryAccess.ensure_viewer(@viewer)
          Platform::Security::RepositoryAccess.accessible_repository_ids(repository_ids: repository_ids)
        end
      else
        def associated_repository_ids(repository_ids: nil)
          Platform::Security::RepositoryAccess.accessible_repository_ids(repository_ids: repository_ids)
        end
      end

      # Returns true if this object is _not_ public
      # and the current request is not a public API request.
      #
      # (Sometimes, methods on private types might get called by public types,
      #  so we want to also check the current request,
      #  to make sure we're not leaking data)
      def hidden_from_public?(object_type)
        type_is_internal_only = !object_type.visibility.include?(:public)
        # We allow API requests to the _internal_ schema, so that we can continue supporting
        # external clients who query the internal schema. It would be nice to _not_
        # do that, but we have to support it for now.
        current_request_is_not_public = (@target == :internal) || (@origin != ORIGIN_API)

        if type_is_internal_only && current_request_is_not_public && @operation_id
          # track that we're returning this object while it has no proper permission checks
          GitHub.dogstats.increment(
            "graphql.permissions.hidden_from_public_accessed",
            tags: ["type:#{object_type}", "query_owning_catalog_service:#{@query_owning_catalog_service}", "query_name:#{@query_name}"],
          )
        end

        type_is_internal_only && current_request_is_not_public
      end

      # Public: Determine if a request is of external origin.
      #
      # Returns false for internal requests, true for everything else.
      def external_request?
        @origin == ORIGIN_INTERNAL ? false : true
      end

      # Helper used in permission checks that depend on another object
      def typed_can_access?(type_name_or_class, object)
        return Promise.resolve(true) if object.nil?

        type_defn_class = case type_name_or_class
        when String
          Platform::Objects.const_get(type_name_or_class)
        when Class
          type_name_or_class
        else
          raise Errors::Internal, "Expected string or class, not: #{type_name_or_class.class}"
        end

        @typed_api_can_access_cache[type_defn_class].fetch(object) do
          type_name = type_defn_class.graphql_name
          auth_check_promise = Promise.resolve(type_defn_class.async_api_can_access?(self, object))
          result = perform_api_access_check(auth_check_promise, object, type_name)
          @typed_api_can_access_cache[type_defn_class][object] = result
        end
      end

      def can_access?(object)
        type_name = Platform::Helpers::NodeIdentification.type_name_from_object(object)
        type_defn_class = if type_name
          begin
            Platform::Objects.const_get(type_name)
          rescue NameError
            # e.g. type_name is "ProjectCards";
            # there is no "Platform::Objects::ProjectCards"
            nil
          end
        end

        if type_defn_class && type_defn_class.respond_to?(:async_api_can_access?)
          auth_check_promise = Promise.resolve(type_defn_class.async_api_can_access?(self, object))
          perform_api_access_check(auth_check_promise, object, type_name)
        else
          case object
          when Hash
            # Can't be resolved to a type
            Promise.resolve(true)
          when Platform::ConnectionWrappers::Relation,
              Platform::ConnectionWrappers::CommitHistory,
              Platform::ConnectionWrappers::ProjectCards,
              Platform::ConnectionWrappers::StableArray,
              Platform::ConnectionWrappers::ManifestDependenciesConnection,
              Platform::ConnectionWrappers::Newsies,
              Platform::ConnectionWrappers::Notifications,
              Platform::ConnectionWrappers::Timeline,
              Platform::ConnectionWrappers::SearchQuery,
              Platform::ConnectionWrappers::ElasticSearchQuery,
              Platform::ConnectionWrappers::RepositoryRecommendationConnection,
              Platform::ConnectionWrappers::AuditLogQuery,
              Platform::ConnectionWrappers::DriftwoodQuery,
              Platform::ConnectionWrappers::CursorCollection
            # Connections wrap lists which are filtered _before_ creating the connection.
            # The connection objects themselves should contain a filtered list,
            # so allow them through.
            Promise.resolve(true)
          when Platform::ConnectionWrappers::PageInfo
            # PageInfo doesn't need auth
            Promise.resolve(true)
          when ::Star,
            ::OauthAccess
            # This object backs an edge, and doesn't have a check here
            Promise.resolve(true)
          when nil
            # you get a `nil`, _you_ get a `nil`!
            Promise.resolve(true)
          when Platform::Errors::Unprocessable
            Promise.resolve(true)
          when Platform::Objects::Query
            # Used by the `Query.relay` field
            Promise.resolve(true)
          else
            raise_permission_missing(type_name, object)
          end
        end
      end

      # Helper used in permission checks that depend on another mutation
      def typed_can_modify?(type_name, **kwargs)
        type_defn_class = Platform::Mutations.const_get(type_name)

        # async_api_can_modify? may return a Promise or a Boolean; wrap it in
        # a Promise so this method always returns a Promise
        Promise.resolve(type_defn_class.async_api_can_modify?(self, **kwargs))
      end

      def can_modify?(type_name, object)
        # Make sure that this instance is configured correctly
        if @operation != :mutation
          raise Platform::Errors::Internal, "@operation = :mutation is required to run #can_modify"
        end

        if object.nil?
          raise Errors::NotFound.new("`#{type_name}` could not resolve an object to mutate")
        elsif respond_to?(type_name)
          GitHub.dogstats.time("platform.authorization.can_modify.time", sample_rate: 0.1, tags: ["type_name:#{type_name}"]) do
            Promise.resolve(public_send(type_name, object)).then do |accessible|
              if accessible == false
                raise Errors::Forbidden.new("#{@viewer} does not have the correct permissions to execute `#{type_name}`")
              elsif accessible == true
                true
              else
                # The resolved value was neither `true` nor `false`,
                # it might be some kind of accident
                err = Errors::Internal.new("Platform::Authorization::Permission##{type_name} resolved to instance of #{accessible.class}, but it should resolve to `true` or `false`.")
                if Rails.env.production?
                  Failbot.report(err)
                  false
                else
                  raise err # rubocop:disable GitHub/UsePlatformErrors
                end
              end
            end
          end
        else
          raise_permission_missing(type_name, object)
        end
      end

      def belongs_to_issue_event(event)
        Promise.all([event.async_issue, event.async_repository]).then do |issue, repo|
          async_owner_if_org(repo).then do |org|
            # in the majority of cases, this repository is the same as the preloaded repo,
            # but it might not be for some events. For example, the MergedEvent may represent
            # a cross-repository PR, so there's the head repository to consider, as well as
            # the base. In those cases, the second repo must be loaded. In all other cases,
            # this is a no-op.
            issue.async_repository.then do
              issue.async_pull_request.then do # this issue might be a PR 🙄
                access_allowed?(:list_issue_timeline, resource: issue, repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
              end
            end
          end
        end
      end

      def viewer_has_limited_repo_access?(repo, org)
        return true if repo.public?
        return true if access_allowed?(:get_repo,
          resource: repo,
          current_repo: repo,
          current_org: org,
          user: @viewer,
          allow_integrations: true,
          allow_user_via_granular_actor: true,
        )

        false
      end

      def has_admin_resource_read_access?(resource:, repo:)
        async_owner_if_org(repo).then do |org|
          case resource
          when :protected_branches
            access_allowed?(:read_branch_protection, resource: repo, current_repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
          when :deploy_keys
            return false unless repo.resources.administration.readable_by?(@viewer)
            access_allowed?(:list_repo_keys, resource: repo, current_repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
          else
            raise Platform::Errors::Internal, "Unexpected resource type #{resource}. Only `:protected_branches` and `:deploy_keys` are allowed."
          end
        end
      end

      def async_can_list_vulnerability_alerts?(repo)
        async_owner_if_org(repo).then do |org|
          Promise.all([repo.async_parent, repo.async_owner, repo.async_organization]).then do
            access_allowed?(:read_vulnerability_alerts, resource: repo, current_repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true, raise_on_error: false)
          end
        end
      end

      def async_can_read_vulnerability_alert?(alert)
        async_repo_and_org_owner(alert).then do |repo, org|
          Promise.all([repo.async_parent, repo.async_owner]).then do
            access_allowed?(:read_vulnerability_alerts, resource: repo, current_repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
          end
        end
      end

      alias_method :async_can_read_vulnerability_alerts_thread?, :async_can_read_vulnerability_alert?
      alias_method :async_can_read_dependabot_update?, :async_can_read_vulnerability_alert?

      def async_can_write_vulnerability_alert?(alert)
        async_repo_and_org_owner(alert).then do |repo, org|
          Promise.all([repo.async_parent, repo.async_owner]).then do
            access_allowed?(:write_vulnerability_alerts, resource: repo, current_repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
          end
        end
      end

      def async_can_list_deployments?(repo:)
        async_owner_if_org(repo).then do |org|
          access_allowed?(:list_deployments, resource: repo, current_repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      def async_can_list_dependency_graphs?(repo)
        async_owner_if_org(repo).then do |org|
          access_allowed?(:list_dependency_graphs, repo: repo, resource: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      def async_can_list_stargazers?(repo)
        async_owner_if_org(repo).then do |org|
          access_allowed?(:list_stargazers, resource: repo, current_repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      def async_can_list_gist_stargazers?(gist)
        gist.async_user.then do |owner|
          org = owner.is_a?(Organization) ? owner : nil
          access_allowed?(:list_gist_stars, resource: gist, current_org: org, current_repo: nil, allow_integrations: false, allow_user_via_granular_actor: true)
        end
      end

      def async_can_list_gist_forks?(gist)
        gist.async_user.then do |owner|
          org = owner.is_a?(Organization) ? owner : nil
          access_allowed?(:list_gist_forks, resource: gist, current_org: org, current_repo: nil, allow_integrations: false, allow_user_via_granular_actor: true)
        end
      end

      def async_can_list_private_repos?(owner)
        access_allowed_promise = case owner
        when Organization
          access_allowed = access_allowed?(:v4_list_private_repos, resource: owner, organization: owner, current_repo: nil, allow_integrations: true, allow_user_via_granular_actor: true)
          Promise.resolve(access_allowed)
        when User
          access_allowed = access_allowed?(:v4_list_private_repos, resource: owner, current_repo: nil, current_org: nil, allow_integrations: true, allow_user_via_granular_actor: true)
          Promise.resolve(access_allowed)
        when Repository
          async_owner_if_org(owner).then do |org|
            access_allowed?(:list_forks, resource: owner, current_repo: owner, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
          end
        when RepositoryNetwork
          # This previously fell into the else below, as something have gone wrong if we hit that code we want to raise there.
          Promise.resolve(false)
        when Topic
          Promise.resolve(false)
        else # should never get to this point
          raise Errors::Internal.new("Unexpected owner: #{owner.class} tried to list private repositories")
        end

        access_allowed_promise.then do |access_allowed|
          access_allowed
        end
      end

      def can_access_private_contributions?
        # Want to use this when constructing a Contribution::Collector, so don't want to raise an
        # error but rather get false.
        access_allowed?(:v4_read_user_private, resource: viewer, current_repo: nil,
                       current_org: nil, allow_user_via_granular_actor: false,
                       allow_integrations: true, raise_on_error: false)
      end

      def can_list_private_org_members?(org)
        access_allowed?(:v4_list_private_org_members, resource: org, organization: org, current_repo: nil, allow_integrations: true, allow_user_via_granular_actor: true)
      end

      def can_list_private_business_members?(business)
        business.owner?(viewer) || viewer.site_admin?
      end

      def can_list_business_outside_collaborators?(business)
        business.owner?(viewer) || viewer.site_admin?
      end

      def can_list_enterprise_installations?(owner)
        owner.adminable_by?(viewer) || viewer.site_admin?
      end

      def can_view_organization_settings?(business)
        business.owner?(viewer)
      end

      def async_can_list_collaborators?(repo_or_project)
        async_owner_if_org(repo_or_project).then do |org|
          if repo_or_project.is_a?(Project)
            repository_id = repo_or_project.owner_type == "Repository" ? repo_or_project.owner_id : nil
          else
            repository_id = repo_or_project.try(:id) || repo_or_project.try(:repo).try(:id)
          end

          access_allowed?(:list_collaborators, resource: repo_or_project, current_repo: repo_or_project, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true, associated_repository_ids: associated_repository_ids(repository_ids: repository_id.nil? ? nil : [repository_id]))
        end
      end

      def async_integration_can_read_public_key?(key)
        # @oauth may be nil. need to pre-load its authorization if there is one
        async_oauth_authorization = @oauth&.async_authorization

        Promise.all([async_oauth_authorization]).then do
          access_allowed?(:read_public_key, user: @viewer, resource: key, current_repo: nil, organization: nil, allow_integrations: false, allow_user_via_granular_actor: true, installation_required: false)
        end
      end

      def can_list_gists?(owner: nil)
        org = owner.is_a?(Organization) ? owner : nil
        access_allowed?(:list_gists, resource: Platform::PublicResource.new, organization: org, current_repo: nil, allow_integrations: false, allow_user_via_granular_actor: true) # rubocop:disable GitHub/PublicResource EMUs don't have Gists
      end

      def async_can_list_gist_comments?(owner)
        if owner.is_a?(Gist)
          owner.async_user.then do |gist_owner|
            org = gist_owner.is_a?(Organization) ? gist_owner : nil
            access_allowed?(:list_gist_comments, resource: owner, current_org: org, current_repo: nil, allow_integrations: false, allow_user_via_granular_actor: true)
          end
        else # it's a User
          if integration_bot_or_user_request?
            # This raises an error
            forbidden = create_check.set_forbidden_message("Resource not accessible by integration")
            Promise.resolve(forbidden)
          else
            Promise.resolve(owner == @viewer)
          end
        end
      end

      def can_list_user_secret_gists?(owner: nil)
        org = owner.is_a?(Organization) ? owner : nil
        access_allowed?(:list_user_secret_gists, resource: owner, target: owner, organization: org, current_repo: nil, allow_integrations: false, allow_user_via_granular_actor: true)
      end

      def async_can_list_milestones?(repo)
        async_owner_if_org(repo).then do |org|
          access_allowed?(:list_milestones, repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      def async_can_list_releases?(repo)
        async_owner_if_org(repo).then do |org|
          access_allowed?(:list_releases, repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      def async_can_list_draft_releases?(repo)
        async_owner_if_org(repo).then do |org|
          access_allowed?(:list_draft_releases, repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true, raise_on_error: false)
        end
      end

      def async_can_get_full_repo?(repo)
        return Promise.resolve(true) if repo.public? || !Platform.requires_scope?(@origin)

        if integration_bot_or_user_request?
          async_owner_if_org(repo).then do |org|
            access_allowed?(:get_repo, resource: repo, current_repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
          end
        else
          access = Api::AccessControl.scope?(@viewer, "repo")
          Promise.resolve(access)
        end

      end

      def async_can_get_repo_temp_clone_token?(repo)
        async_owner_if_org(repo).then do |org|
          access_allowed?(:get_temp_clone_token, resource: repo, current_repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: false)
        end
      end

      def async_can_list_repo_labels?(repo)
        async_owner_if_org(repo).then do |org|
          access_allowed?(:list_repo_labels, resource: repo, repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      def can_list_issues?(owner, repo)
        org = owner.is_a?(Organization) ? owner : nil
        access_allowed?(:list_issues, resource: repo, repo: repo, organization: org, allow_integrations: true, allow_user_via_granular_actor: true)
      end

      def can_list_teams?(org)
        access_allowed?(:v4_list_teams, organization: org, resource: org, current_repo: nil, allow_integrations: true, allow_user_via_granular_actor: true)
      end

      def can_list_team_invitations?(team)
        org = team.organization
        access_allowed?(:v4_list_team_invitations, team: team, organization: org, resource: org, current_repo: nil, allow_integrations: true, allow_user_via_granular_actor: true)
      end

      def async_can_list_pull_requests?(repo)
        Promise.all([async_owner_if_org(repo), repo.async_parent]).then do |org, _|
          access_allowed?(:list_pull_requests, repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      def async_can_list_commit_comments?(repo)
        async_owner_if_org(repo).then do |org|
          access_allowed?(:v4_list_commit_comments, resource: repo, repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      def can_list_user_notifications?(user)
        return false if user.id != @viewer.id # bail early
        access_allowed?(:v4_get_thread, resource: user, current_repo: nil, current_org: nil, allow_integrations: false, allow_user_via_granular_actor: false)
      end

      def can_get_public_org_member?
        ALWAYS_PUBLIC
      end

      def can_list_private_org_memberships?(user)
        # We should never be able to get an Org here, but a guard is added just in case something changes
        if user.is_a?(Organization)
          raise Errors::Internal.new("Organization unexpectedly passed to can_list_private_org_memberships?")
        end

        resource = Platform::GraphqlUserResource.new(permissions: {})
        access_allowed?(:v4_get_user_org_memberships, raise_on_error: false, current_repo: nil, current_org: nil, resource: resource, tfca: user, allow_integrations: true, allow_user_via_granular_actor: true)
      end

      def can_list_projects?(owner)
        current_org = nil
        current_repo = nil
        if owner.is_a?(Organization)
          current_org = owner
        elsif owner.is_a?(Repository)
          current_repo = owner
        elsif owner.is_a?(Issue) || owner.is_a?(PullRequest)
          owner = owner.repository
          current_repo = owner
        end

        access_allowed?(:list_projects, resource: owner, owner: owner, organization: current_org, current_repo: current_repo, allow_integrations: true, allow_user_via_granular_actor: true)
      end

      def can_view_org_billing_email?(org)
        access_allowed?(
          :v4_view_org_settings,
          resource: org,
          current_org: org,
          current_repo: nil,
          allow_integrations: false,
          allow_user_via_granular_actor: false,
        )
      end

      def can_view_two_factor_enabled?(org)
        access_allowed?(
          :v4_view_org_settings,
          resource: org,
          current_org: org,
          current_repo: nil,
          allow_integrations: false,
          allow_user_via_granular_actor: false,
        )
      end

      def can_view_ip_allow_list_settings?(org)
        access_allowed?(
          :v4_view_org_settings,
          resource: org,
          current_org: org,
          current_repo: nil,
          allow_integrations: false,
          allow_user_via_granular_actor: false,
        )
      end

      def can_view_verifiable_domains?(org)
        access_allowed?(
          :v4_view_org_settings,
          resource: org,
          current_org: org,
          current_repo: nil,
          allow_integrations: true,
          allow_user_via_granular_actor: false,
        )
      end

      def async_api_can_access_audit_entry?(audit_entry)
        access_promises = []
        entry_action = audit_entry.action

        if AuditLogEntry.user_action_names.include?(entry_action)
          access_promises << async_api_can_access_user_audit_entry?(audit_entry)
        end

        if AuditLogEntry.organization_action_names.include?(entry_action)
          access_promises << async_api_can_access_organization_audit_entry?(audit_entry)
        end

        if AuditLogEntry.business_action_names.include?(entry_action)
          access_promises << async_api_can_access_business_audit_entry?(audit_entry)
        end

        Promise.all(access_promises).then(&:any?)
      end

      def async_api_can_access_business_audit_entry?(audit_entry)
        async_biz = Loaders::ActiveRecord.load(::Business, audit_entry.get(:business_id))
        async_orgs = if audit_entry.document["org_id"].kind_of?(Array)
          # Some audit entries have a list of org_ids they may be associated
          # with. These are found under the same `org_id` field as any field in
          # Elasticsearch can have zero or more values.
          audit_entry.document["org_id"].map do |org_id|
            Loaders::ActiveRecord.load(::Organization, org_id)
          end
        else
          [Loaders::ActiveRecord.load(::Organization, audit_entry.document["org_id"])]
        end

        Promise.all([async_biz, async_orgs].flatten).then do |entities|
          business = entities.shift
          orgs = entities

          if audit_entry.get(:business_id)
            # If a business_id is present, we only authorize the admin of this
            # business. We pass `current_org` to enforce OAP.
            orgs.map do |organization|
              access_allowed?(
                :read_business_audit_log,
                resource: business,
                current_org: organization,
                current_repo: nil,
                allow_integrations: false,
                allow_user_via_granular_actor: false,
              )
            end.any?
          elsif audit_entry.get(:org_id)
            # If no business_id is present, but org_id(s) are present, we
            # fetch the businesses associated to the orgs and authorize anyone
            # who is an admin of one of those businesses.
            orgs.map do |organization|
              access_allowed?(
                :read_business_and_org_audit_log,
                resource: nil,
                current_org: organization,
                current_repo: nil,
                allow_integrations: false,
                allow_user_via_granular_actor: false,
              )
            end.any?
          else
            false
          end
        end
      end

      def async_api_can_access_organization_audit_entry?(audit_entry)
        async_organization = Loaders::ActiveRecord.load(::Organization, audit_entry.document["org_id"])
        async_organization.then do |organization|
          can_access_audit_log_for_organization?(organization)
        end
      end

      def can_access_audit_log_for_organization?(organization)
        access_allowed?(
          :v4_read_org_audit_log,
          resource: organization,
          current_org: organization,
          current_repo: nil,
          allow_integrations: false,
          allow_user_via_granular_actor: false,
        )
      end

      def async_api_can_access_user_audit_entry?(audit_entry)
        Promise.all([
          Loaders::ActiveRecord.load(::User, audit_entry.document["actor_id"]),
          Loaders::ActiveRecord.load(::Organization, audit_entry.document["org_id"]),
        ]).then do |actor, organization|
          can_access_audit_log_for_user?(actor, organization)
        end
      end

      def can_access_audit_log_for_user?(actor, organization)
        access_allowed?(
          :read_user_audit_log,
          user: viewer,
          resource: actor,
          current_org: organization,
          current_repo: nil,
          allow_integrations: false,
          allow_user_via_granular_actor: false,
        )
      end

      def async_viewer_can_see_audit_entry?(audit_entry)
        entry_action = audit_entry.action

        # Some user actions are also visible to organization and business admin
        # so we don't return false until we check those as well.
        return true if AuditLogEntry.user_action_names.include?(entry_action) && can_see_user_audit_entry?(audit_entry)

        viewer_promises = []

        if AuditLogEntry.organization_action_names.include?(entry_action)
          viewer_promises << async_can_see_organization_audit_entry?(audit_entry)
        end

        if AuditLogEntry.business_action_names.include?(entry_action)
          viewer_promises << async_can_see_business_audit_entry?(audit_entry)
        end

        Promise.all(viewer_promises).then(&:any?)
      end

      def async_can_see_business_audit_entry?(audit_entry)
        if audit_entry.get(:business_id)
          Loaders::ActiveRecord.load(::Business, audit_entry.get(:business_id)).then do |business|
            business&.async_adminable_by?(viewer)
          end
        elsif audit_entry.get(:org_id)
          # If business_id not present, try to load business through org association
          async_orgs = if audit_entry.document["org_id"].kind_of?(Array)
            # Some audit entries have a list of org_ids they may be associated
            # with. These are found under the same `org_id` field as any field in
            # Elasticsearch can have zero or more values.
            audit_entry.document["org_id"].map do |org_id|
              Loaders::ActiveRecord.load(::Organization, org_id)
            end
          else
            [Loaders::ActiveRecord.load(::Organization, audit_entry.document["org_id"])]
          end

          Promise.all(async_orgs).then do |orgs|
            async_adminables = orgs.compact.map { |org| org.async_business.then { |biz| biz&.async_adminable_by?(viewer) } }
            Promise.all(async_adminables).then(&:any?)
          end
        else
          Promise.resolve(false)
        end
      end

      def async_can_see_organization_audit_entry?(audit_entry)
        async_organization = Loaders::ActiveRecord.load(::Organization, audit_entry.get(:org_id))
        async_organization.then { |org| org&.async_can_read_org_audit_logs?(viewer) }
      end

      def can_see_user_audit_entry?(audit_entry)
        viewer.id == audit_entry.get(:actor_id)
      end

      def can_access_organization_domain_emails?(organization)
        access_allowed?(
          :read_org_member_domain_emails,
          resource: organization,
          organization: organization,
          current_repo: nil,
          allow_integrations: true,
          allow_user_via_granular_actor: true,
        )
      end

      def fetch_reactable_egress_access_role(reactable)
        case reactable
        when CommitComment
          :create_commit_comment_reaction
        when DiscussionPost, DiscussionPostReply
          :create_team_discussion_related_reaction
        when RepositoryAdvisory, RepositoryAdvisoryComment
          :create_repository_advisory_related_reaction
        when Issue, IssueComment, PullRequest
          :create_issue_related_reaction
        when PullRequestReview, PullRequestReviewComment
          :create_pull_request_review_comment_reaction
        when Discussion, DiscussionComment
          :create_discussion_comment_reaction
        when Release
          :create_release_reaction
        else
          raise Errors::Internal, "Unknown reactable type `#{reactable.class}`!"
        end
      end

      def has_scope?(scope)
        return true unless Platform.requires_scope?(@origin)
        return false if @scopes.nil?
        @scopes.include?(scope)
      end

      def current_integratable_owner
        if @integration.present?
          @integration.async_owner.sync
        elsif @oauth_app.present?
          @oauth_app.async_user.sync
        end
      end

      def filter_permissible_repository_resources(owner, scope, resource:, filter_spam: false)
        auth_type = if integration_bot_request?
          "server-server-GitHub-app"
        elsif integration_user_request?
          "user-server-GitHub-app"
        elsif user_programmatic_access_request?
          "user-programmatic-access"
        else
          "non-GitHub-app"
        end

        GitHub.dogstats.time("platform.authorization.filter_permissible_repository_resources.time", tags: ["auth_type: #{auth_type}"]) do
          is_cross_schema_domain = %w(issues pull_requests issue_events issue_comments commit_comments).include?(scope.table_name)

          unique_repo_ids = nil
          repo_scope = nil
          exp_repo_scope = nil

          repo_ids = if integration_bot_request?
            installation = @viewer.installation

            unless installation
              if is_cross_schema_domain
                return having_public_repositories_scope(scope, unique_repository_ids(scope), filter_spam)
              else
                return scope.public_scope
              end
            end

            permissions = installation.permissions[resource]
            resource = Platform::GraphqlUserResource.new(permissions: permissions)
            if owner == @viewer
              target = installation.async_target.sync
              target_query = target.user? ? "repositories.owner_id" : "repositories.organization_id"

              if is_cross_schema_domain
                unique_repo_ids = unique_repository_ids(scope)
                repo_scope = repository_scope(filter_spam).
                  where(id: unique_repo_ids).
                  where("#{target_query} = ?", target.id)
              else
                scope = scope.joins(:repository).where("#{target_query} = ?", target.id)
              end
            end

            # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
            owner.associated_repository_ids & installation.repository_ids
            # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded
          elsif ProgrammaticActor::RepositoryFilter.applicable?(@viewer)
            subject_ids = if owner == @viewer
              @viewer.associated_repository_ids # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
            else
              # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
              @viewer.associated_repository_ids | owner.associated_repository_ids
              # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded
            end

            associated_installation_repository_ids = ProgrammaticActor::RepositoryFilter.perform(
              actor: @viewer,
              repository_ids: subject_ids,
              resource: resource,
            )

            if owner == @viewer
              associated_installation_repository_ids
            else
              # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
              owner.associated_repository_ids & associated_repository_ids & associated_installation_repository_ids
              # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded
            end
          elsif owner == @viewer
            associated_repository_ids # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
          else
            # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
            owner.associated_repository_ids & associated_repository_ids
            # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded
          end

          unless ProgrammaticActor::RepositoryFilter.applicable?(@viewer)
            if !access_allowed?(:v4_list_user_private_resources, raise_on_error: false, resource: resource, tfca: owner, current_repo: nil, current_org: nil, allow_integrations: true, allow_user_via_granular_actor: true)
              if is_cross_schema_domain
                unique_repo_ids ||= unique_repository_ids(scope)
                scope = scope.where(repository_id: repo_scope.pluck(:id)) if repo_scope
                return having_public_repositories_scope(scope, unique_repo_ids, filter_spam)
              else
                return scope.public_scope
              end
            end
          end

          scope = scope.from("#{scope.quoted_table_name} IGNORE INDEX FOR ORDER BY (PRIMARY)")

          # unique_repo_ids may or may not have been plucked above, but beyond this point it is required by all remaining scope modifications
          unique_repo_ids ||= unique_repository_ids(scope)

          scope = if repo_ids.any?
            repo_scope ||= repository_scope(filter_spam)

            filtered_repo_ids = repository_ids_from(scope: repo_scope, unique_repo_ids: unique_repo_ids, repo_ids: repo_ids)
            scope.where(repository_id: filtered_repo_ids)
          else
            scope = scope.where(repository_id: repo_scope.pluck(:id)) if repo_scope
            having_public_repositories_scope(scope, unique_repo_ids, filter_spam)
          end
          scope
        end
      end

      def repository_ids_from(scope:, unique_repo_ids:, repo_ids:)
        pre_filtered_repo_ids = unique_repo_ids
        # if already exists an id in clause, the result would be the intersection of the two
        if scope.where_values_hash.key?("id")
          where_values_ids = scope.where_values_hash["id"]
          where_values_ids = [where_values_ids] unless where_values_ids.is_a?(Array)
          pre_filtered_repo_ids &= where_values_ids
        end
        # id IN (pre_filtered_repo_ids) AND (public = true OR (id IN (repo_ids))
        # ids that could fall in (public = true ...)
        might_be_public = pre_filtered_repo_ids - repo_ids
        # ids that could fall in (OR (id IN (repo_ids))
        pre_filtered_repo_ids &= repo_ids
        if might_be_public.any?
          # add ids that are public
          pre_filtered_repo_ids += Repository.where(id: might_be_public, public: true)
            .annotate("filter_permissible_repository_resources")
            .pluck(:id)
        end

        scope.rewhere(id: pre_filtered_repo_ids)
          .annotate("filter_permissible_repository_resources")
          .pluck(:id)
      end

      def unique_repository_ids(scope)
        scope.select(:repository_id).distinct.pluck(:repository_id)
      end

      def repository_scope(filter_spam)
        repo_scope = Repository.active
        filter_spam ? repo_scope.filter_spam_and_disabled_for(@viewer) : repo_scope
      end

      def having_public_repositories_scope(base_scope, repo_ids, filter_spam)
        public_repo_ids = repository_scope(filter_spam).
          where(id: repo_ids, public: true).
          pluck(:id)
        base_scope.where(repository_id: public_repo_ids)
      end

      def filtered_permissible_repository_scope(owner, repository_ids, resource:, include_repos_from_enterprise_managed_business: false)
        return Repository.none if repository_ids.empty?

        auth_type = if integration_bot_request?
          "server-server-GitHub-app"
        elsif integration_user_request?
          "user-server-GitHub-app"
        elsif user_programmatic_access_request?
          "user-programmatic-access"
        else
          "non-GitHub-app"
        end

        GitHub.dogstats.time("platform.authorization.filter_permissible_repository_ids_resources.time", tags: ["auth_type: #{auth_type}"]) do
          accessible_repository_ids = if integration_bot_request?
            if installation = @viewer.installation
              permissions = installation.permissions[resource]
              resource = Platform::GraphqlUserResource.new(permissions: permissions)

              if owner == @viewer
                target = installation.async_target.sync
                target_query = target.user? ? "owner_id" : "organization_id"

                # Limit to repositories owned by the installation target
                repository_ids &= Repository.where("#{target_query} = ?", target.id).ids
              end

              owner.associated_repository_ids(repository_ids: repository_ids) &
                installation.repository_ids(repository_ids: repository_ids)
            else
              []
            end
          elsif ProgrammaticActor::RepositoryFilter.applicable?(@viewer)
            subject_ids = if owner == viewer
              @viewer.associated_repository_ids(repository_ids: repository_ids)
            else
              @viewer.associated_repository_ids(repository_ids: repository_ids) |
                owner.associated_repository_ids(repository_ids: repository_ids)
            end

            associated_installation_repository_ids = ProgrammaticActor::RepositoryFilter.perform(
              actor: @viewer,
              repository_ids: subject_ids,
              resource: resource,
            )

            if owner == @viewer
              associated_installation_repository_ids
            else
              owner.associated_repository_ids(repository_ids: repository_ids) &
                associated_repository_ids(repository_ids: repository_ids) &
                associated_installation_repository_ids
            end
          elsif owner == @viewer
            owned_by_viewer = true
            associated_repository_ids(repository_ids: repository_ids)
          else
            owner.associated_repository_ids(repository_ids: repository_ids) &
              associated_repository_ids(repository_ids: repository_ids)
          end

          return Repository.none if repository_ids.empty?

          unless ProgrammaticActor::RepositoryFilter.applicable?(@viewer)
            if !access_allowed?(:v4_list_user_private_resources, raise_on_error: false, resource: resource, tfca: owner, current_repo: nil, current_org: nil, allow_integrations: true, allow_user_via_granular_actor: true)
              return Repositories::Public.where_public(repository_ids)
            end
          end

          # With enterprise-managed-businesses its #likely that the internal repositories for the viewer's business won't
          # be included in the results of the `associated_repository_ids call. Those repos aren't indirectly accessible to the
          # user, as the organizations' base permissions levels are set
          # to `:none`. Under the hood, `associated_repository_ids` queries the Ability table to find
          # repos the user doesn't have direct access to.
          # See https://thehub.github.com/epd/engineering/products-and-services/authorization/abilities/#organization-owned-repositories
          #
          # We manually add those repos to the list of accessible repos via the `InternalRepository` table here.
          enterprise_managed_repository_ids = if include_repos_from_enterprise_managed_business
            accessible_enterprise_managed_repository_ids(repository_ids: repository_ids)
          else
            []
          end

          accessible_repository_ids |= enterprise_managed_repository_ids

          accessible_repository_ids &= repository_ids

          Repositories::Public.accessible_repositories(
            repository_ids: repository_ids,
            associated_repository_ids: accessible_repository_ids,
          )
        end
      end

      # Takes the given repository ids and returns those that are accessible to the viewer
      # via their enterprise-managed-businesses.
      private def accessible_enterprise_managed_repository_ids(repository_ids:)
        if GitHub.multi_tenant_enterprise?
          InternalRepository.where(business_id: @viewer.business_id, repository_id: repository_ids).pluck(:repository_id)
        elsif @viewer.try(:is_enterprise_managed?)
          InternalRepository.where(business_id: @viewer.enterprise_managed_business.id, repository_id: repository_ids).pluck(:repository_id)
        else
          []
        end
      end

      # Returns an array of filtered Repository ids for a owner
      def filter_permissible_repository_ids(owner, repository_ids, resource:)
        filtered_permissible_repository_scope(owner, repository_ids, resource: resource).ids
      end

      def load_pull_and_issue(obj)
        obj.async_pull_request.then do |pull|
          pull.async_issue.then do |_issue|
            pull
          end
        end
      end

      def rewrite_reaction_subject(subject)
        if subject.is_a?(Issue) && subject.pull_request_id.present?
          subject.async_pull_request.then do |pull|
            ["PullRequest", pull]
          end
        else
          Promise.resolve(true).then do
            subject_type = Platform::Helpers::NodeIdentification.type_name_from_object(subject)
            [subject_type, subject]
          end
        end
      end

      def access_allowed?(action, options = {})
        validate_access_allowed_args!(options) if Rails.env.test?
        return access_allowed_api_origin(action, options) if public_origin?
        access_allowed_internal_origin(action, options)
      end

      def public_origin?
        @origin == Platform::ORIGIN_API
      end

      def access_allowed_api_origin(action, options)
        check_instance = create_check(
          current_repo: current_repo(options),
          current_org: current_org(options),
          resource: options[:resource],
        )

        check_instance.access_allowed?(action, **options)
      end

      def access_allowed_internal_origin(action, options)
        return true unless @enforce_conditional_access_via_graphql

        rfca = resource_for_conditional_access(action: action, options: options) do
          # use other access_allowed? arguments as fallback
          current_org(options) || current_repo(options)
        end
        # CAP Framework does not support _async calls, so let's resolve
        # TFCA outside of the framework and return a promise
        rfca.async_target_for_conditional_access.then do |tfca|
          tags = ["origin:#{@origin}", "api_action:#{action}", "rfca_class:#{rfca&.class&.name}", "tfca_class:#{tfca&.class&.name}"]
          GitHub.dogstats.increment("cap.enforcer.internal_api.rfca.count", tags: tags)
          enforce_conditional_access_policies(tfca)
          true
        end
      end

      def validate_access_allowed_args!(options)
        # make sure that `@current_repo` and `@current_org` get set explicitly
        # via the provided options in order to make sure authz is not bypassed
        repo_message = nil
        org_message = nil

        unless explicit_repo_arg?(options)
          repo_message = "* repository: `access_allowed?` must be provided a repo to use; please set the `current_repo:` option. Pass `nil` to `current_repo:` if repo is not applicable to this permission check.\n"
        end

        unless explicit_org_arg?(options)
          org_message = "* organization: `access_allowed?` must be provided an organization to use; please set the `current_org:` option. Pass `nil` to `current_org:` if org is not applicable to this permission check.\n"
        end

        if repo_message || org_message
          message = <<~MSG
            `access_allowed?` must be called with the right options:
          #{repo_message}
          #{org_message}
          MSG

          raise ArgumentError, message # rubocop:disable GitHub/UsePlatformErrors
        end
      end

      def current_repo(options)
        options[:current_repo] || options[:repo]
      end

      def current_org(options)
        options[:current_org] || options[:organization]
      end

      # did the callsite explicitly pass the repository argument?
      def explicit_repo_arg?(options)
        options.key?(:repo) || options.key?(:current_repo)
      end

      # did the callsite explicitly pass the organization argument?
      def explicit_org_arg?(options)
        options.key?(:organization) || options.key?(:current_org)
      end

      # Used to extract conditional access policy enforcement time after the completion of all authorization logic.
      def cap_aggregate_time
        @cap_enforcer.aggregate_time if @enforce_conditional_access_via_graphql
      end

      def enforce_conditional_access_policies(resource, policies: @cap_enforcer.conditional_access_policies)
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        cache_val = @cap_resource_policy_cache[policies][resource]
        cache_hit = !cache_val.nil?
        if cache_hit
          @cap_resource_policy_cache[policies][resource]
        else
          @cap_resource_policy_cache[policies][resource] = @cap_enforcer.enforce_conditional_access_policies(resource, policies: policies)
        end
      ensure
        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        time = (end_time - T.must(start_time)) * 1_000
        anon = @viewer.blank?
        tags = ["anonymous:#{anon}", "cache_hit:#{cache_hit}"]
        GitHub.dogstats.distribution("cap.internal.api.enforcement.dist", time, tags: tags)
        @cap_enforcer.increase_agreggate_enforcement_time(time)
      end

      # Is the request by a user logged in with Oauth,
      # via an Integration?
      #
      # Returns a boolean.
      def integration_user_request?
        viewer&.oauth_access&.integration_application_type?
      end

      # Is the request by a user logged in with Oauth,
      # via an Integration installed globally?
      #
      # Returns a boolean.
      def global_integration_user_request?
        return false unless integration_user_request?
        Apps::Internal.capable?(:installed_globally, app: viewer.oauth_access.application)
      end

      # This logic is in Authorization, so delegate to a check
      def integration_bot_request?
        create_check.integration_bot_request?
      end

      def integration_bot_or_user_request?
        integration_bot_request? || integration_user_request?
      end

      # Is this request by a user via a UserProgrammaticAccess?
      def user_programmatic_access_request?
        viewer&.using_auth_via_user_programmatic_access?
      end

      # If this org/user combination would require a SAML credential,
      # but one is not present, then return `false` and add an error message.
      #
      # This check returns true for internal requests, because those handle SAML checks in their own ways.
      # @return [Boolean]
      def organization_credential_authorized_if_external_request?(org, resource:)
        (!external_request?) ||
          create_check(current_org: org, raise_on_error: true).organization_credential_authorized?(resource: resource)
      end

      # Throws if actor type unable to access the resource
      def check_actor_limiter(klazz, context)
        @actor_limiter_cache.fetch(klazz) do
          @actor_limiter_cache[klazz] = Platform::Helpers::ActorLimiter.check(klazz, context)
        end
      end

      private

      def fetch_integration_permissions(resource)
        @integration.default_permissions[resource]
      end

      def perform_api_access_check(auth_check_promise, object, type_name)
        GitHub.dogstats.time("platform.authorization.can_access.time", sample_rate: 0.001, tags: ["type_name:#{type_name}"]) do
          promises = []

          if @integration.present?
            promises << @integration.async_latest_version.then do |version|
              version.async_default_permission_records
            end
            promises << @integration.async_bot
          end

          if @installation.present?
            promises << @installation.async_target
          end

          Promise.all(promises).then { auth_check_promise }
        end
      end

      def raise_permission_missing(type_name, object)
        error = Errors::NotImplemented.new <<~ERROR
          Tried to run a permissions check but failed.

          Checking an instance of #{object.class.name}.

          Treating it as GraphQL type #{type_name.inspect}.

          No corresponding method was found in `app/platform/authorization/permission.rb`. To fix this error, choose one:

          - Add a mapping to `Platform::Helpers::NodeIdentification.type_name_from_object` so that
            instances of `#{object.class.name}` are mapped to a proper GraphQL object type.

          - Or, if `#{type_name}` is the correct GraphQL type for instances of `#{object.class.name}`,
            implement `def self.async_api_can_access?(permission, #{type_name.underscore})` in `app/platform/objects/#{type_name.underscore}.rb`

          For more information, see https://thehub.github.com/engineering/development-and-ops/public-apis/graphql/security/authz/
          or post a CI failure in #graphql.
        ERROR
        if Rails.env.production?
          # Fail soft in production, because we don't know exactly how
          # many cases there are of this. Return `true` because
          # that's historically how it behaved by default.
          # Remove this branch after these needles are gone.
          Failbot.report(error)
          Promise.resolve(true)
        else
          # In other environments, fail hard, so that we get off of
          # the default behavior of returning true
          raise error # rubocop:disable GitHub/UsePlatformErrors
        end
      end

      def create_check(current_repo: nil, current_org: nil, resource: nil, raise_on_error: nil)
        Authorization::PermissionCheck.new(
          current_user: @viewer,
          integration: @integration,
          installation: @installation,
          operation: @operation,
          resource: resource,
          oauth: @oauth,
          response: @response,
          mutation: @mutation,
          current_repo: current_repo,
          current_org: current_org,
          saml_enforced_cache: @saml_enforced_cache,
          credential_authorization_cache: @credential_authorization_cache,
          oauth_app_authorization_cache: @oauth_app_authorization_cache,
          cap_resource_policy_cache: @cap_resource_policy_cache,
          remote_ip: @remote_ip,
          request_hmac: @request_hmac,
          request_client_ip: @request_client_ip,
          raise_on_error: raise_on_error,
          authenticated_actor_using_web_session: @authenticated_actor_using_web_session,
          user_session: @user_session,
          request_access_security_header: @request_access_security_header,
          request_forwarded_for: @request_forwarded_for,
        )
      end
    end
  end
end
