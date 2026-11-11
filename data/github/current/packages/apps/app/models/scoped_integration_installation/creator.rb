# typed: true
# frozen_string_literal: true

class ScopedIntegrationInstallation
  class Creator < ScopedIntegrationInstallation::Creators::Base
    include ScopedIntegrationInstallation::PermissionRowsGenerator

    CACHE_NAMESPACE = "generate_scoped_token"
    INSTALL_ON_ALL_REPOSITORIES = :all
    INSTALL_ON_ALL_SELECTED_REPOSITORIES = :selected

    # The max repository checks are behind a feature flag
    MAX_REPOSITORY_IDS = 500
    TOO_MANY_REPOSITORY_IDS_MSG = "Too many repositories for installation. Please supply up to %{count} repositories using the `repositories` or `repository_ids` request attributes or try again later"

    # Error message returned when a `store` scope is requested but the parent
    # installation does not have the `Organization/stores` permission required
    # to grant Store/* permissions.
    STORE_SCOPE_NOT_PERMITTED_MSG = "The installation does not have permission to scope tokens to a store"
    STORE_NOT_AVAILABLE_TO_TARGET_MSG = "The store provided does not exist or is not accessible to the parent installation"

    attr_reader :parent, :repositories, :repository_selection, :scoped_permissions, :entry_point, :store
    delegate :integration, :target, to: :parent

    def self.perform(parent, repositories: [], permissions: {}, expires: true, log_data: {}, entry_point: nil, store: nil)
      new(parent, repositories: repositories, permissions: permissions, expires: expires, log_data: log_data, entry_point: entry_point, store: store).perform
    end

    def self.perform_with_cache(parent, repositories: [], permissions: {}, log_data: {}, entry_point: nil, store: nil)
      new(parent, repositories: repositories, permissions: permissions, log_data: log_data, entry_point: entry_point, store: store).perform_with_cache
    end

    def initialize(parent, repositories: [], permissions: {}, expires: true, log_data: {}, entry_point: nil, store: nil)
      @parent       = parent
      @repositories = repositories
      @expires      = expires
      @log_data     = log_data
      @entry_point  = entry_point
      @store        = store

      case repositories
      when INSTALL_ON_ALL_REPOSITORIES
        @repositories = repositories
        @repository_selection = INSTALL_ON_ALL_REPOSITORIES
      when INSTALL_ON_ALL_SELECTED_REPOSITORIES
        @repositories = @parent.repositories
        @repository_selection = INSTALL_ON_ALL_SELECTED_REPOSITORIES
      else
        @repository_selection = @repositories = Array(@repositories)
      end

      @permissions = if permissions == :none
        {}
      elsif permissions.present?
        permissions
      elsif store.present?
        {}
      else
        parent.version.default_permissions
      end

      @scoped_permissions = ScopedIntegrationInstallation::Permissions.new(
        @parent,               # installation
        @repository_selection, # repositories
        :create,               # action
        permissions: @permissions,
      )
    end

    def perform
      GitHub.tracer.in_span("ScopedIntegrationInstallation::Creator#perform", kind: :internal) do |_span|
        validate_permissions!
        block_too_many_repos!

        create_record

        @scoped_installation.instrument_creation

        GitHub.dogstats.increment("scoped_integration_installation.create", tags: ["result:success"])

        Result.success(@scoped_installation)
      rescue ActiveRecord::RecordInvalid, Result::Error => e
        GitHub.dogstats.increment("scoped_integration_installation.create", tags: ["result:failed"])
        Result.failed e.message
      end
    end

    def perform_with_cache
      GitHub.tracer.in_span("ScopedIntegrationInstallation::Creator#perform_with_cache", kind: :internal) do |_span|
        cache = ::ScopedIntegrationInstallation::Cache.new(
          CACHE_NAMESPACE, parent, repository_cache_fragment, permissions_cache_fragment
        )

        if cache.exist?
          if (installation = cache.get) && valid_permissions? && !installation.expired?
            extend_expires_at(installation)
            result = Result.success(installation, found_cached: true)
            cache.set(result)
            return result
          end
        end

        result = perform
        cache.set(result)
      end
    end

    def self.permission_row(installation, subject, action, expires_at, ar_attributes = false)
      expires_at = expires_at.to_i if expires_at.present?

      ::Permissions::Service.installation_attributes_hash(
        actor: installation,
        subject: subject,
        action: action,
        expires_at: expires_at,
      )
    end

    private

    # TODO: This is identical to
    # SiteScopedIntegrationInstallation::Creator#app_attributes
    def app_attributes(subject, action)
      [
        @scoped_installation,
        subject,
        action,
        expires_at
      ]
    end

    def validate_permissions!
      GitHub.tracer.in_span("ScopedIntegrationInstallation::Creator#validate_permissions", kind: :internal) do |_span|
        check = scoped_permissions.check
        raise_error check.error_message unless check.permitted?

        if scoped_to_store?
          raise_error STORE_SCOPE_NOT_PERMITTED_MSG unless store_scope_permitted?
          raise_error STORE_NOT_AVAILABLE_TO_TARGET_MSG unless parent_on_org_with_requested_store?
        end
      end
    end

    def create_record
      options = { parent: parent }
      options[:expires_at] = expires_at

      details = ScopedInstallations::AuthorizationDetails::Builder.build

      case target
      when Business
        if business_permissions_to_grant.any?
          details.add_permissions_selection(
            resource_type: ScopedInstallations::AuthorizationDetails::ResourceType::Business,
            permissions: business_permissions_to_grant,
            selection: [target.id]
          )
        end
      when User
        if repository_permissions_to_grant.any?
          selection =
            if installing_on_all_repositories? || installing_on_all_selected_repositories?
              ScopedInstallations::AuthorizationDetails::Selection::Parent
            else
              repositories.map(&:id)
            end

          details.add_permissions_selection(
            resource_type: ScopedInstallations::AuthorizationDetails::ResourceType::Repository,
            permissions: repository_permissions_to_grant,
            selection: selection
          )
        end

        if target.is_a?(Organization) && organization_permissions_to_grant.any?
          details.add_permissions_selection(
            resource_type: ScopedInstallations::AuthorizationDetails::ResourceType::Organization,
            permissions: organization_permissions_to_grant,
            selection: [target.id]
          )
        end
      end

      if scoped_to_store?
        details.add_permissions_selection(
          resource_type: ScopedInstallations::AuthorizationDetails::ResourceType::Store,
          permissions: store_permissions_to_grant,
          selection: [store.id]
        )
      end

      begin
        details.validate!
        options[:authorization_details] = details.serialize
      rescue JSON::Schema::ValidationError, KeyError => e
        raise ScopedIntegrationInstallation::Result::Error, "There was a problem while granting permissions"
      end

      @scoped_installation = ActiveRecord::Base.connected_to(role: :writing) do
        ScopedIntegrationInstallation.create!(options)
      end
    end

    memoize def permissions_cache_fragment
      # Sort by string-keyed name and stringify values so semantically
      # equivalent permission hashes produce the same cache key regardless
      # of key order, key type (Symbol vs String), or value type.
      fragment = if @permissions.present?
        @permissions
        .each_with_object([]) { |(k, v), acc| acc << [k.to_s, v.to_s] }
        .sort_by!(&:first)
      else
        @permissions
      end

      # When the request is not store-scoped, preserve the legacy fragment
      # shape (just the permissions hash) so existing cache keys do not
      # change. When a store scope is present, append it so that distinct
      # stores cache distinctly.
      return fragment unless @store.present?
      [fragment, @store.id]
    end

    def permission_rows_for_repositories
      GitHub.tracer.in_span("ScopedIntegrationInstallation::Creator#permission_rows_for_repositories", kind: :internal) do |span|
        span.set_attribute("gh.installation.repositories.count", repositories.count)
        GitHub.dogstats.distribution("scoped_integration_installation.repositories.size", repositories.count, tags: ["subset:#{installing_on_subset_of_selected_repositories?}"])

        permissions = repository_permissions_to_grant
        subject_permission_rows(subjects: repositories, permissions: permissions)
      end
    end

    def permission_rows_for_all_repositories
      GitHub.tracer.in_span("ScopedIntegrationInstallation::Creator#permission_rows_for_all_repositories", kind: :internal) do |_span|
        repository_permissions_to_grant.map do |permission, action|
          subject = target.repository_resources.public_send(permission.to_s)
          self.class.permission_row(*app_attributes(subject, action))
        end
      end
    end

    def permission_rows_for_business
      GitHub.tracer.in_span("ScopedIntegrationInstallation::Creator#permission_rows_for_business", kind: :internal) do |_span|
        subject_permission_rows(subjects: [@scoped_installation.target], permissions: business_permissions_to_grant)
      end
    end

    def permission_rows_for_organization
      GitHub.tracer.in_span("ScopedIntegrationInstallation::Creator#permission_rows_for_organization", kind: :internal) do |_span|
        subject_permission_rows(subjects: [@scoped_installation.target], permissions: organization_permissions_to_grant)
      end
    end

    def grant_permissions(rows)
      ::Permissions::Service.grant_permissions!(rows, stats_key: "scoped_integration_installation", entry_point: entry_point)
    end

    def subject_permission_rows(subjects:, permissions:)
      rows = subjects.flat_map do |subject|
        permissions.map do |resource, action|
          resource_subject = subject.resources.public_send(resource)
          self.class.permission_row(*app_attributes(resource_subject, action))
        end
      end
    end

    def installing_on_all_repositories?
      INSTALL_ON_ALL_REPOSITORIES == @repositories
    end

    memoize def transient_version
      default_permissions = scoped_permissions.valid_for_parent

      # Remove the `organization_packages` subject type because we no longer
      # grant package access in this creator.
      default_permissions.delete("organization_packages")

      IntegrationVersion.new(
        integration: parent.integration,
        parent_installation: parent,
        default_permissions: default_permissions,
      )
    end

    def repository_cache_fragment
      return @repository_cache_fragment if defined?(@repository_cache_fragment)

      @repository_cache_fragment = case repositories
      when INSTALL_ON_ALL_REPOSITORIES
        "all"
      when ActiveRecord::Relation
        repositories.order(:id).pluck(:id)
      else
        repositories.map(&:id).sort
      end

      @repository_cache_fragment = @repository_cache_fragment.to_s
    end

    def installing_on_all_selected_repositories?
      repository_selection == INSTALL_ON_ALL_SELECTED_REPOSITORIES
    end

    def installing_on_subset_of_selected_repositories?
      !installing_on_all_repositories? && !installing_on_all_selected_repositories?
    end

    # Mitigate incident where write amplification happens with large numbers
    # of repository ids
    # https://github.com/github/availability/issues/1410
    def block_too_many_repos!
      @log_data[:installations_repositories_all] = installing_on_all_repositories?
      return if installing_on_all_repositories?

      repositories_count = repositories.count
      @log_data[:repositories_count] = repositories_count
      return if repositories_count <= MAX_REPOSITORY_IDS

      # if the original FF is enabled, enforce the repository limit unconditionally
      enforced_globally = integration&.feature_flag_enabled?(:installations_max_repository_ids, default: false)
      # only enforce the repo limit if the user explicitly specified a list of repositories
      enforced_on_subset = installing_on_subset_of_selected_repositories? && integration&.feature_flag_enabled?(:installation_max_repositories_enforce_on_subset, default: false)

      # Always log something so we can get insights into the limits necessary to protect the database
      GitHub.logger.info(
        "Detected an App creating a scoped installation access token due to exceeding MAX_REPOSITORY_IDS",
        "gh.request_id" => GitHub.context[:request_id],
        "gh.integration.id" => integration.id,
        "gh.installation.repositories_count" => repositories_count,
        "gh.installation.target.id" => target.id,
        "gh.installation.repos_subset" => installing_on_subset_of_selected_repositories?,
        "gh.installation.max_repos_flipper_enabled" => enforced_globally,
        "gh.installation.max_repos_subset_enforced" => enforced_on_subset
      )

      @log_data[:circuit_breaker_enabled] = enforced_globally
      @log_data[:installations_repositories_subset] = installing_on_subset_of_selected_repositories?

      if enforced_globally || enforced_on_subset
        raise_error I18n.interpolate(TOO_MANY_REPOSITORY_IDS_MSG, { count: MAX_REPOSITORY_IDS })
      end
    end

    def remaining_expiry_tag_prefix
      "scoped_integration_installation"
    end

    def raise_error(e)
      raise Result::Error, e
    end

    memoize def permissions_to_grant
      transient_version.default_permissions
    end

    memoize def business_permissions_to_grant
      Business::Resources.filter(permissions_to_grant)
    end

    memoize def organization_permissions_to_grant
      Organization::Resources.filter(permissions_to_grant)
    end

    memoize def repository_permissions_to_grant
      Repository::Resources.filter(permissions_to_grant)
    end

    # Internal: Was this Creator invoked with a `store:` scope?
    def scoped_to_store?
      @store.present?
    end

    # Internal: Look up the parent installation's `stores` permission directly
    # (not through the requested permissions hash). Used both to determine
    # whether scoping to a store is permitted and to default the implicit
    # Store/* permission level.
    #
    # Returns a Symbol (:read / :write / :admin) or nil.
    sig { returns(T.nilable(Symbol)) }
    def parent_org_stores_action_from_parent
      action = parent.version.default_permissions["stores"]
      action.presence&.to_sym
    end

    def store_scope_permitted?
      parent_org_stores_action_from_parent.present?
    end

    def parent_on_org_with_requested_store?
      parent.target_id == store.owner_id
    end

    # Internal: The implicit Store/* permissions to grant when the token is
    # scoped to a store, derived from the parent installation's
    # `Organization/stores` access level.
    #
    # Mapping:
    #   Org/stores: read  -> Store/contents: read,  Store/metadata: read
    #   Org/stores: write -> Store/contents: write, Store/metadata: read
    #   Org/stores: admin -> Store/contents: write, Store/metadata: read,
    #                        Store/administration: write
    #
    # Store/contents is capped at :write because admin-level "contents" has
    # no defined meaning today; the additional admin capability (e.g. store
    # deletion) is expressed via Store/administration: write instead.
    # Store/metadata is always read (default/required/automatic), similar
    # to repository metadata.
    def store_permissions_to_grant
      action = parent_org_stores_action_from_parent

      perms = {}
      return perms unless action

      perms["contents"] = (action == :admin) ? :write : action
      perms["metadata"] = :read
      perms["administration"] = :write if action == :admin

      perms
    end
  end
end
