# typed: true
# frozen_string_literal: true

class ScopedIntegrationInstallation
  class Creator < ScopedIntegrationInstallation::Creators::Base
    include ScopedIntegrationInstallation::PermissionRowsGenerator

    CACHE_NAMESPACE = "generate_scoped_token"
    DEFAULT_BATCH_SIZE = 1_000
    INSTALL_ON_ALL_REPOSITORIES = :all
    INSTALL_ON_ALL_SELECTED_REPOSITORIES = :selected

    # The max permission rows checks are behind a flipper flag
    MAX_PERMISSION_ROWS = 40_000

    # The max repository checks are behind a flipper flag
    MAX_REPOSITORY_IDS = 500
    TOO_MANY_REPOSITORY_IDS_MSG = "Too many repositories for installation. Please supply up to %{count} repositories using the `repositories` or `repository_ids` request attributes or try again later"

    TOO_MANY_PERMISSIONS_MSG = "Too many repositories for installation. Please reduce the number of repositories this application has access to to %{count} repositories or fewer, or use the `repositories` or `repository_ids` request attributes to list up to %{count} repositories in the request. You can also reduce the number of permissions requested, or set the application to be installed on all repositories in the organization."

    attr_reader :parent, :repositories, :repository_selection, :scoped_permissions, :entry_point
    delegate :integration, :target, to: :parent

    def self.perform(parent, repositories: [], permissions: {}, expires: true, log_data: {}, entry_point: nil)
      new(parent, repositories: repositories, permissions: permissions, expires: expires, log_data: log_data, entry_point: entry_point).perform
    end

    def self.perform_with_cache(parent, repositories: [], permissions: {}, log_data: {}, entry_point: nil)
      new(parent, repositories: repositories, permissions: permissions, log_data: log_data, entry_point: entry_point).perform_with_cache
    end

    def initialize(parent, repositories: [], permissions: {}, expires: true, log_data: {}, entry_point: nil)
      @parent       = parent
      @repositories = repositories
      @expires      = expires
      @log_data     = log_data
      @entry_point  = entry_point

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
        block_too_many_permissions!

        begin
          create_record

          rows = []

          if installing_on_all_repositories?
            rows.concat(permission_rows_for_all_repositories)
          else
            rows.concat(permission_rows_for_repositories)
          end

          if target.is_a?(Organization)
            rows.concat(permission_rows_for_organization)
          end

          grant_permissions(rows)
        rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => err
          ActiveRecord::Base.connected_to(role: :writing) do
            @scoped_installation&.destroy
          end

          Failbot.report(err)
          raise_error err
        end

        @scoped_installation.instrument_creation

        GitHub.dogstats.increment("scoped_integration_installation.create", tags: ["result:success"])

        Result.success(@scoped_installation)
      rescue Result::Error => e
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
      end
    end

    def create_record
      options = { parent: parent }
      options[:expires_at] = expires_at

      if parent.feature_enabled?(:scoped_installation_with_authorization_details)
        if transient_version.permissions_of_type(Repository).any?
          if installing_on_all_repositories? || installing_on_all_selected_repositories?
            new_repo_selection = ScopedInstallations::AuthorizationDetails::Selection::Parent
          else
            new_repo_selection = ScopedInstallations::AuthorizationDetails::Selection::Subset
            new_repo_ids = repositories.map(&:id)
          end
        end

        details, error = ScopedInstallations::AuthorizationDetails::Serializer.generate(
          target: target,
          permissions: transient_version.default_permissions,
          repository_selection: new_repo_selection,
          repository_ids: new_repo_ids
        )

        if error.present?
          # .report! does not raise which is always backwards in my mind.
          # We want to send the issue to Sentry without disrupting the customer experience.
          err = StandardError.new(error)
          Failbot.report!(error)
        else
          options[:authorization_details] = details
        end
      end

      @scoped_installation = ActiveRecord::Base.connected_to(role: :writing) do
        ScopedIntegrationInstallation.create!(options)
      end
    end

    memoize def permissions_cache_fragment
      @permissions
    end

    def permission_rows_for_repositories
      GitHub.tracer.in_span("ScopedIntegrationInstallation::Creator#permission_rows_for_repositories", kind: :internal) do |span|
        span.set_attribute("gh.installation.repositories.count", repositories.count)
        GitHub.dogstats.distribution("scoped_integration_installation.repositories.size", repositories.count, tags: ["subset:#{installing_on_subset_of_selected_repositories?}"])

        permissions = transient_version.permissions_of_type(Repository)
        subject_permission_rows(subjects: repositories, permissions: permissions)
      end
    end

    def permission_rows_for_all_repositories
      GitHub.tracer.in_span("ScopedIntegrationInstallation::Creator#permission_rows_for_all_repositories", kind: :internal) do |_span|
        transient_version.permissions_of_type(Repository).map do |permission, action|
          subject = target.repository_resources.public_send(permission.to_s)
          self.class.permission_row(*app_attributes(subject, action))
        end
      end
    end

    def permission_rows_for_organization
      GitHub.tracer.in_span("ScopedIntegrationInstallation::Creator#permission_rows_for_organization", kind: :internal) do |_span|
        permissions = transient_version.permissions_of_type(Organization)
        subject_permission_rows(subjects: [@scoped_installation.target], permissions: permissions)
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
      @repositories == INSTALL_ON_ALL_REPOSITORIES
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
      enforced_globally = GitHub.flipper[:installations_max_repository_ids].enabled?(integration)
      # only enforce the repo limit if the user explicitly specified a list of repositories
      enforced_on_subset = installing_on_subset_of_selected_repositories? && GitHub.flipper[:installation_max_repositories_enforce_on_subset].enabled?(integration)

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

    def block_too_many_permissions!
      # Safety switch to turn the whole validation off for rollout.
      return unless GitHub.flipper[:installations_max_permission_rows_toggle].enabled?(integration)

      return if transient_version.default_permissions.empty?
      return if installing_on_all_repositories?

      total_rows_to_be_written = calculate_total_permission_rows_to_be_written
      return if total_rows_to_be_written <= MAX_PERMISSION_ROWS

      flipper_enabled = GitHub.flipper[:installations_max_permission_rows].enabled?(integration)

      repository_limit = calculate_repository_limit

      # Always log something so we can get insights into the limits necessary to protect the database
      GitHub.logger.info(
        "Detected an App creating a scoped installation access token due to exceeding MAX_PERMISSION_ROWS",
        "gh.request_id" => GitHub.context[:request_id],
        "gh.integration.id" => integration.id,
        "gh.installation.repositories_count" => repositories.count,
        "gh.installation.repository_limit" => repository_limit,
        "gh.installation.permission_rows_count" => total_rows_to_be_written,
        "gh.installation.target.id" => target.id,
        "gh.installation.repos_subset" => installing_on_subset_of_selected_repositories?,
        "gh.installation.max_permission_rows_flipper_enabled" => flipper_enabled
      )

      if flipper_enabled
        raise_error I18n.interpolate(TOO_MANY_PERMISSIONS_MSG, { count: repository_limit })
      end
    end

    def remaining_expiry_tag_prefix
      "scoped_integration_installation"
    end

    def raise_error(e)
      raise Result::Error, e
    end

    def calculate_repository_limit
      capacity = MAX_PERMISSION_ROWS

      if target.is_a?(Organization)
        permissions = transient_version.permissions_of_type(Organization)
        capacity -= permissions.keys.count
      end

      repository_permissions_count = transient_version.permissions_of_type(Repository).keys.count

      capacity / repository_permissions_count
    end

    def calculate_total_permission_rows_to_be_written
      total = 0

      permissions = transient_version.permissions_of_type(Repository)
      total += @repositories.count * permissions.keys.count

      if target.is_a?(Organization)
        permissions = transient_version.permissions_of_type(Organization)
        total += permissions.keys.count
      end

      total
    end
  end
end
