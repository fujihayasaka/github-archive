# typed: false
# frozen_string_literal: true

module Platform
  module Objects
    class Query < Platform::Objects::Base
      # This custom field will _skip_ resolution if we've detected
      # that this is a `rateLimit(dryRun: true)` request.
      # (But it still resolves the `rateLimit` fields in that case.)
      # NB: this patch must come before the `include` calls below
      class QueryRootField < Platform::Objects::Base::Field
        def resolve(obj, args, ctx)
          if ctx[:rate_limit_dry_run] && name != "rateLimit"
            ctx.skip
          else
            super
          end
        end
      end
      field_class QueryRootField

      include Platform::Objects::Query::Actions
      include Platform::Objects::Query::Apps
      include Platform::Objects::Query::Advisories
      include Platform::Objects::Query::Blog
      include Platform::Objects::Query::CodeSearch
      include Platform::Objects::Query::CommunityAndSafety
      include Platform::Objects::Query::Discussions
      include Platform::Objects::Query::Enterprise
      include Platform::Objects::Query::Explore
      include Platform::Objects::Query::Features
      include Platform::Objects::Query::Integrations
      include Platform::Objects::Query::Lists
      include Platform::Objects::Query::Marketplace
      include Platform::Objects::Query::Mobile
      include Platform::Objects::Query::Orgs
      include Platform::Objects::Query::Packages
      include Platform::Objects::Query::Pages
      include Platform::Objects::Query::Repositories
      include Platform::Objects::Query::Search
      include Platform::Objects::Query::Sponsors
      include Platform::Objects::Query::SuggestedNavigationDestinations
      include Platform::Objects::Query::TradeCompliance
      include Platform::Objects::Query::User

      implements Interfaces::Searchable
      # This is a workaround for the fact that the root query object is not a node
      # but it is required to implement the Node interface in order to support
      # the @refetchable directive.
      allow_legacy_global_id_implementation
      implements Platform::Interfaces::Node # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      def id
        "RootQueryObject"
      end

      ALLOWED_QUERY_STRING_PARAMS   = %w(lab).freeze

      description "The query root of GitHub's GraphQL interface."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      #
      # Requires no special permissions as this is the root query object query {}
      # Has to be accessible for everyone to run queries
      def self.async_api_can_access?(_permission, _object)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      # Required because Query.relay returns `Query`
      #
      # Requires no special permissions as this is the root query object
      # Has to be accessible for everyone to run queries
      def self.async_viewer_can_see?(permission, object)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      field :node, Platform::Interfaces::Node, null: true,
        description: "Fetches an object given its ID." do
          argument :id, ID, required: true, description: "ID of the object."
        end

      def node(id:)
        context.schema.object_from_id(id, context) #rubocop: disable GitHub/UntypedObjectId
      end

      field :nodes, [Platform::Interfaces::Node, null: true],
        null: false,
        description: "Lookup nodes by a list of IDs." do
        argument :ids, [ID], "The list of node IDs.", required: true
      end

      def nodes(ids:)
        if Platform.unsafe_origin?(@context[:origin]) && ids.size > 100
          raise Errors::ArgumentLimit, "You may not provide more than 100 node ids; you provided #{ids.size}."
        end

        handle_node = ->(n) { n }
        # An error handler so that some IDs can be `NOT_FOUND` and replaced with `nil`
        # while others are correctly returned.
        # (Without this handler, a single raised `NOT_FOUND` would nullify the whole response)
        handle_error = -> (err) {
          if err.is_a?(GraphQL::ExecutionError)
            # Let GraphQL-Ruby handle this error & add it to the response
            err
          else
            # This error should cause a crash, it's an internal error of some kind
            raise err # rubocop:disable GitHub/UsePlatformErrors
          end
        }

        # For each of the given IDs, load an object by that ID
        ids.map do |id|
          # Wrap the whole `.object_from_id` call in a promise so that any eagerly-raised errors
          # are also handled by the `handle_error` block
          Promise.resolve(nil).then do
            context.schema.object_from_id(id, context) #rubocop: disable GitHub/UntypedObjectId
          end.then(handle_node, handle_error)
        end
      end

      field :resource, Interfaces::UniformResourceLocatable, description: "Lookup resource by a URL.", null: true do
        argument :url, Scalars::URI, "The URL.", required: true
      end

      def resource(**arguments)
        url = arguments[:url]
        begin
          params = if GitHub.gist_domain? && GitHub.gist_host_name == url.host
            parse_gist_path(url.path)
          else
            GitHub::Application.routes.recognize_path(url.path, method: :get)
          end
        rescue ActionController::RoutingError, TypeError
          params = {}
        end

        # This will append on query string values which we will allow to pass.
        # The initial use-case was that workflows need an additional url querystring value: lab=true in
        # order to properly identify lab workfows.  The controlled ALLOWED_QUERY_STRING_PARAMS will be used
        # to ensure we only let through a controlled set of values and not just any user-supplied input.
        # If this were deemed safe then we could simply allow all querystring values to pass-through.
        # Until then (and since we only have 1 use-case) we can keep the surface-area of this very minimal.
        query_string_params = (url.query_values || {}).slice(*ALLOWED_QUERY_STRING_PARAMS).symbolize_keys

        # Prefer params from path over query string values (in the rare case of collisions)
        params = query_string_params.merge(params)

        types = {
          %w[files disambiguate] => Objects::Repository,
          %w[issues show] => Objects::Issue,
          %w[milestones show] => Objects::Milestone,
          ["orgs/team_discussions", "show"] => Objects::TeamDiscussion,
          %w[pull_requests show] => Objects::PullRequest,
          %w[commit show] => Objects::Commit,
          %w[releases show] => Objects::Release,
          %w[profiles show] => Objects::User,
          ["actions/workflow_runs", "show"] => Objects::WorkflowRun,
          %w[actions index] => Objects::Workflow,
          ["actions/workflow_runs", "workflow_file"] => Objects::WorkflowRunFile,
          ["gists/gists", "show"] => Objects::Gist,
        }

        type = types[[params[:controller], params[:action]]]
        object = type.respond_to?(:load_from_params) ? type.load_from_params(params) : nil

        Promise.resolve(object).then do |object|
          if object
            context[:permission].typed_can_see?(type, object).then do |readable|
              readable ? object : nil
            end
          end
        end
      end

      field :viewer, Objects::User, description: "The currently authenticated user.", null: false

      def viewer
        @context[:viewer]
      end

      field :safe_viewer, Objects::User, description: "The currently authenticated user. Can be null if the user is not authenticated.", visibility: :internal, null: true

      def safe_viewer
        @context[:viewer]
      end

      field :requester, Unions::Requester, description: "Who the query was requested by.", null: false, visibility: :under_development

      def requester
        case @context[:viewer]
        when ::User
          Platform::Models::RequestingUser.new(@context[:viewer])
        end
      end

      field :rate_limit, Objects::RateLimit, description: "The client's rate limit information.", null: true do
        argument :dry_run, Boolean, "If true, calculate the cost for the query without evaluating it", default_value: false, required: false
      end

      def rate_limit(**arguments)
        if GitHub.rate_limiting_enabled? && @context[:cost_limiter].present?
          @context[:cost_limiter].rate_limit
        end
      end

      field :temp_nullable_viewer, Objects::User, visibility: :internal, description: "A (temporary) nullable version of viewer", null: true do
      end

      def temp_nullable_viewer
        @context[:viewer]
      end

      field :relay, Query, description: "Workaround for re-exposing the root query object. (Refer to https://github.com/facebook/relay/issues/112 for more information.)", null: false

      def relay
        self
      end

      field :meta, Objects::GitHubMetadata, description: "Return information about the GitHub instance", null: false

      def meta
        {
          verifiable_password_authentication: GitHub.auth.verifiable?,
          hooks: GitHub.hook_ips,
          git: GitHub.git_ips,
          pages: GitHub.pages_a_record_ips,
          importer: GitHub.github_source_importer_ips,
          github_enterprise_importer: GitHub.github_enterprise_importer_ips,
          installed_version: GitHub.version_number,
          github_services_sha: GitHub.current_sha,
        }
      end

      private

      def parse_gist_path(path)
        # Dotcom runs without the Gist routes loaded so the path has to be parsed manually
        _prefix, user_id, gist_id = path.split("/")
        {
          format: :html,
          controller: "gists/gists",
          action: "show",
          gist_id:,
          user_id:,
        }
      end
    end
  end
end
