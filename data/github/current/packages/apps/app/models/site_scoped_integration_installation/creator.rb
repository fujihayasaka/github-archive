# typed: true
# frozen_string_literal: true

class SiteScopedIntegrationInstallation
  class Creator < ScopedIntegrationInstallation::Creators::Base
    include ScopedIntegrationInstallation::PermissionRowsGenerator

    CACHE_NAMESPACE = "generate_site_scoped_token"
    INSTALL_ON_ALL_REPOSITORIES = :all
    DEFAULT_BATCH_SIZE = 1_000
    MAXIMUM_EXPIRATION_EXTENSION_THRESHOLD = 5.hours
    EXPIRATION_WINDOW = 72.hours

    attr_reader :integration, :target, :repositories, :permissions, :version, :codespaces,
                :extended_permissions, :should_grant_packages_permissions, :rate_limit, :entry_point

    # TODO: Consider...
    # Do we need a superficially separate class here that's just for site scoped
    # installations? I don't think we actually care at the call-sites so maybe
    # this could be removed in favor of just using the
    # ScopedIntegrationInstallation::Result as-is.
    class Result < ScopedIntegrationInstallation::Result; end

    def self.perform(
          integration,
          target,
          repositories: [],
          codespaces: [],
          permissions: {},
          extended_permissions: {},
          expires: true,
          elevated_read_access_on_target: false,
          should_grant_packages_permissions: false,
          rate_limit: nil,
          entry_point: nil
        )
      new(integration,
          target,
          repositories: repositories,
          codespaces: codespaces,
          permissions: permissions,
          extended_permissions: extended_permissions,
          expires: expires,
          elevated_read_access_on_target: elevated_read_access_on_target,
          should_grant_packages_permissions: should_grant_packages_permissions,
          rate_limit: rate_limit,
          entry_point: entry_point
         ).perform
    end

    def self.perform_with_cache(
          integration,
          target,
          repositories: [],
          codespaces: [],
          permissions: {},
          extended_permissions: {},
          expires: true,
          elevated_read_access_on_target: false,
          should_grant_packages_permissions: false,
          rate_limit: nil,
          entry_point: nil
        )
      new(integration,
          target,
          repositories: repositories,
          codespaces: codespaces,
          permissions: permissions,
          extended_permissions: extended_permissions,
          expires: expires,
          elevated_read_access_on_target: elevated_read_access_on_target,
          should_grant_packages_permissions: should_grant_packages_permissions,
          rate_limit: rate_limit,
          entry_point: entry_point
         ).perform_with_cache
    end

    def initialize(
          integration,
          target,
          repositories: [],
          codespaces: [],
          permissions: {},
          extended_permissions: {},
          expires: true,
          elevated_read_access_on_target: false,
          should_grant_packages_permissions: false,
          rate_limit: nil,
          entry_point: nil
        )
      @integration = integration
      @target = target
      @expires = expires
      @repositories = repositories
      @rate_limit = rate_limit
      @codespaces = codespaces
      @extended_permissions = extended_permissions
      @elevated_read_access_on_target = elevated_read_access_on_target
      @should_grant_packages_permissions = should_grant_packages_permissions
      @entry_point = entry_point

      unless @repositories == INSTALL_ON_ALL_REPOSITORIES
        @repositories = Array(@repositories)
      end

      @permissions = permissions.present? ? permissions : integration.default_permissions
      @authorization_details = ScopedInstallations::AuthorizationDetails::Structs::V1.new
    end

    memoize def expiry
      EXPIRATION_WINDOW.from_now
    end

    def perform
      validate_permissions!

      if @integration.feature_enabled?(:write_authorization_details_for_site_scoped_integration_installations)
        @site_scoped_installation = build_record
        permissions = synthesize_permission_rows

        _, error_message = ScopedInstallations::AuthorizationDetails::Serializer.validate(@authorization_details.serialize)
        raise_error(error_message) if error_message

        authorization_details = @authorization_details.serialize

        ActiveRecord::Base.connected_to(role: :writing) do
          @site_scoped_installation.save!
        end

        # These were all synthesized before the installation was persisted.
        permissions.each { |permission| permission[:actor_id] = @site_scoped_installation.id }

        grant_permissions!(permissions)

        ActiveRecord::Base.connected_to(role: :writing) do
          @site_scoped_installation.update!(authorization_details: authorization_details)
        end
      else
        create_record
        grant_permissions!(synthesize_permission_rows)
      end

      @site_scoped_installation.instrument_creation

      GitHub.dogstats.increment("site_scoped_integration_installation.create", tags: ["result:success"])
      Result.success(@site_scoped_installation)
    rescue ActiveRecord::ActiveRecordError, ScopedIntegrationInstallation::Result::Error => e
      ActiveRecord::Base.connected_to(role: :writing) do
        # https://github.com/github/ecosystem-apps/issues/5950
        # To save a database DELETE, we only destroy impotent SSII records when
        # they DO NOT expire. Records with an `expires_at` attribute will
        # be automatically cleaned up by pt-archiver.
        @site_scoped_installation&.destroy unless expires?
      end

      GitHub.dogstats.increment("site_scoped_integration_installation.create", tags: ["result:success"])
      Result.failed e.message
    end

    def perform_with_cache
      cache = ::SiteScopedIntegrationInstallation::Cache.new(
        CACHE_NAMESPACE, integration, target, cache_key_fragments
      )

      if cache.exist?
        if (installation = cache.get) && valid_permissions? && !installation.expired?
          extend_expires_at(installation)
          update_rate_limit(installation)
          result = Result.success(installation, found_cached: true)
          cache.set(result)
          return result
        end
      end

      result = perform
      cache.set(result)
    end

    private

    def synthesize_permission_rows
      rows = []

      if installing_on_all_repositories?
        rows.concat(permission_rows_for_all_repositories)
      else
        rows.concat(permission_rows_for_repositories)
      end

      if target.is_a?(Organization)
        options = {
          actor: @site_scoped_installation,
          subjects: [target],
          permissions: organization_permissions(permissions),
          expires_at: expires_at,
        }

        if @integration.feature_enabled?(:write_authorization_details_for_site_scoped_integration_installations)
          options[:authorization_details] = @authorization_details
        end

        rows.concat(permission_rows_for_subjects(**options))
      end

      if @codespaces.present?
        options = {
          integration: integration,
          installation: @site_scoped_installation,
          codespaces: @codespaces,
          expires_at: expires_at,
        }

        if @integration.feature_enabled?(:write_authorization_details_for_site_scoped_integration_installations)
          options[:authorization_details] = @authorization_details
        end

        rows.concat(permission_rows_for_codespaces(**options))
      end

      if @should_grant_packages_permissions || @codespaces.present?
        options = {
          integration: integration,
          installation: @site_scoped_installation,
          target: target,
          repositories: repositories,
          permissions: permissions,
          expires_at: expires_at,
        }

        if @integration.feature_enabled?(:write_authorization_details_for_site_scoped_integration_installations)
          options[:authorization_details] = @authorization_details
        end

        rows.concat(generate_and_validate_permission_rows_for_packages!(**options))
      end

      if @extended_permissions.present?
        rows.concat(permission_rows_for_workflows_and_prs)
      end

      rows
    end

    def remaining_expiry_tag_prefix
      "site_scoped_integration_installation"
    end

    # TODO: This is identical to
    # ScopedIntegrationInstallation::Creator#app_attributes
    def app_attributes(subject, action)
      [
        @site_scoped_installation,
        subject,
        action,
        expires_at,
      ]
    end

    def validate_app_capability!
      unless Apps::Internal.capable?(:installed_globally, app: integration)
        raise_error "Integration can't be globally installed"
      end

      if GitHub.flipper[:disabled_global_apps].enabled?(integration)
        raise_error "Global-Apps is disabled for this integration"
      end
    end

    # Private: Validates this Global App can actually access the requested target/repos.
    #
    # Global Apps are limited by default. During development, integrators can define a
    # set of targets/repos that can be accessible.
    #
    # https://github.com/github/github/pull/139090 describes how the accessible targets can
    # be configured.
    #
    # May raise an error if the App can't access the requested target/repos.
    def validate_limited_access!
      if Apps::Internal.capable?(:limited_access, app: integration)
        accessible_targets = Apps::Internal.property(:accessible_targets, app: integration) || {}
        accessible_targets.transform_keys!(&:downcase)

        target_key = target.login.downcase
        if accessible_targets.empty? || !accessible_targets.has_key?(target_key)
          raise_error "This integration doesn't have access to the given target"
        end

        accessible_repositories = accessible_targets[target_key].map(&:downcase)
        return if accessible_repositories.empty?

        if (repositories.map { |r| r.name.downcase } - accessible_repositories).any?
          raise_error "This integration doesn't have access to all of the requested repositories"
        end
      end
    end

    def validate_global_permissions!
      check = SiteScopedIntegrationInstallation::Permissions.check(
        integration:  integration,
        target:       target,
        repositories: repositories,
        action:       :create,
        permissions:  permissions,
      )

      raise_error check.error_message unless check.permitted?
    end

    def validate_permissions!
      validate_app_capability!
      validate_limited_access!
      validate_global_permissions!
    end

    def build_record
      SiteScopedIntegrationInstallation.build(
        integration: integration,
        target: target,
        rate_limit: @rate_limit,
        expires_at: expires_at,
      )
    end

    def create_record
      options = { integration: integration, target: target, rate_limit: @rate_limit }
      options[:expires_at] = expires_at

      @site_scoped_installation = \
        ActiveRecord::Base.connected_to(role: :writing) do
          SiteScopedIntegrationInstallation.create!(options)
        end
    end

    def grant_permissions!(attributes)
      ::Permissions::Service.grant_permissions!(attributes, entry_point: entry_point)
    end

    def permission_rows_for_repositories
      GitHub.dogstats.distribution("site_scoped_integration_installation.repositories.size", repositories.size)

      installation = IntegrationInstallation.find_by(integration: integration, target: target)

      granting_elevated_read_permissions_on_target = installation.present? && elevated_read_access_on_target?(integration)

      attributes = []

      return attributes if repository_permissions.empty?

      if granting_elevated_read_permissions_on_target
        expected_repository_ids = repositories.map(&:id)
        actual_repository_ids = installation.repository_ids(
          min_action: :read,
          resource: "metadata",
          repository_ids: expected_repository_ids
        )

        # All of the repositories must be part of the installation.
        if (expected_repository_ids - actual_repository_ids).empty?
          attributes.concat(permission_rows_for_elevated_read_permissions_on_target)
        else
          # Because all of the repositories are not apart of the installation
          # we need to set this false to handle the conditional down below.
          granting_elevated_read_permissions_on_target = false
        end
      end

      resource_type = ScopedInstallations::AuthorizationDetails::ResourceType::Repository

      unless granting_elevated_read_permissions_on_target
        if @integration.feature_enabled?(:write_authorization_details_for_site_scoped_integration_installations)
          @authorization_details.set_selection_for(resource_type, ScopedInstallations::AuthorizationDetails::Selection::Subset)
          @authorization_details.set_subject_ids_for(resource_type, repositories.map(&:ability_id))
          @authorization_details.set_subject_types_and_actions_for(resource_type, repository_permissions)
        end
      end

      repository_permissions.each_pair do |permission, action|
        next if action == :read && granting_elevated_read_permissions_on_target

        if granting_elevated_read_permissions_on_target && @integration.feature_enabled?(:write_authorization_details_for_site_scoped_integration_installations)
          @authorization_details.set_asymmetric_for(
            resource_type, permission, action, repositories.map(&:ability_id)
          )
        end

        repositories.each do |repository|
          subject = repository.resources.public_send(permission) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
          attributes << ::ScopedIntegrationInstallation::Creator.permission_row(*app_attributes(subject, action))
        end
      end

      attributes
    end

    def permission_rows_for_elevated_read_permissions_on_target
      return [] if repository_permissions.empty?

      readonly_permissions = repository_permissions.transform_values { :read }

      resource_type = ScopedInstallations::AuthorizationDetails::ResourceType::Repository

      if @integration.feature_enabled?(:write_authorization_details_for_site_scoped_integration_installations)
        @authorization_details.set_selection_for(resource_type, ScopedInstallations::AuthorizationDetails::Selection::All)
        @authorization_details.set_subject_types_and_actions_for(resource_type, readonly_permissions)
      end

      readonly_permissions.flat_map do |permission, action|
        subject = target.repository_resources.public_send(permission) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
        permission_row_for(actor: @site_scoped_installation, subject: subject, action: action, expires_at: expires_at)
      end
    end

    def permission_rows_for_all_repositories
      return [] if repository_permissions.empty?

      resource_type = ScopedInstallations::AuthorizationDetails::ResourceType::Repository

      if @integration.feature_enabled?(:write_authorization_details_for_site_scoped_integration_installations)
        @authorization_details.set_selection_for(resource_type, ScopedInstallations::AuthorizationDetails::Selection::All)
        @authorization_details.set_subject_types_and_actions_for(resource_type, repository_permissions)
      end

      GitHub.tracer.in_span("SiteScopedIntegrationInstallation::Creator#permission_rows_for_all_repositories", kind: :internal) do |_span|
        repository_permissions.map do |permission, action|
          subject = target.repository_resources.public_send(permission.to_s)
          ::ScopedIntegrationInstallation::Creator.permission_row(*app_attributes(subject, action))
        end
      end
    end

    def permission_rows_for_workflows_and_prs
      rows = []

      repositories.each do |repository|
        repo_hash = @extended_permissions.find { |r| r["repository_id"] == repository.id }

        pull_request_permission_rows = permission_rows_for_pull_requests(@site_scoped_installation, repository, repo_hash)
        workflow_run_permission_rows = permission_rows_for_workflow_runs(@site_scoped_installation, repository, repo_hash)

        if @integration.feature_enabled?(:write_authorization_details_for_site_scoped_integration_installations)
          {
            ScopedInstallations::AuthorizationDetails::ResourceType::PullRequest => pull_request_permission_rows,
            ScopedInstallations::AuthorizationDetails::ResourceType::WorkflowRun => workflow_run_permission_rows
          }.each_pair do |resource_type, permission_rows|
            next if permission_rows.empty?

            permission_rows.each do |row|
              resource = row[:subject_type].split("/").last

              @authorization_details.set_asymmetric_for(
                resource_type, resource, row[:action], [row[:subject_id]]
              )
            end
          end
        end

        rows.concat(pull_request_permission_rows)
        rows.concat(workflow_run_permission_rows)
      end

      rows
    end

    def installing_on_all_repositories?
      @repositories == INSTALL_ON_ALL_REPOSITORIES
    end

    memoize def transient_version_permissions
      IntegrationVersion.new(
        integration: integration,
        default_permissions: permissions,
      ).default_permissions
    end

    memoize def repository_permissions
      Repository::Resources.filter(transient_version_permissions)
    end

    def elevated_read_access_on_target?(integration)
      !!@elevated_read_access_on_target && Apps::Internal.capable?(:elevated_read_access_on_target, app: integration)
    end

    def cache_key_fragments
      return cache_key_fragment_without_rate_limit if cache_key_without_rate_limit?

      permissions_cache_key_fragments = merge_cache_key_packages_permissions(permissions)
      repos_fragment = installing_on_all_repositories? ? INSTALL_ON_ALL_REPOSITORIES : repositories.map(&:id).sort

      [
        repos_fragment,
        codespaces.map(&:id).sort,
        permissions_cache_key_fragments,
        extended_permissions,
        should_grant_packages_permissions,
        rate_limit
      ].map(&:to_s).join(":")
    end

    def cache_key_fragment_without_rate_limit
      permissions_cache_key_fragments = merge_cache_key_packages_permissions(permissions)
      repos_fragment = installing_on_all_repositories? ? INSTALL_ON_ALL_REPOSITORIES : repositories.map(&:id).sort

      [
        repos_fragment,
        codespaces.map(&:id).sort,
        permissions_cache_key_fragments,
        extended_permissions,
        should_grant_packages_permissions,
      ].map(&:to_s).join(":")
    end

    def merge_cache_key_packages_permissions(cache_key_fragments)
      return cache_key_fragments unless Apps::Internal.capable?(:manage_packages_permissions, app: integration)
      latest_updated_at = IntegrationAllowedPackage.where(
        repository: repositories, integration_id: integration.id
      ).maximum(:updated_at)
      cache_key_fragments.merge(latest_allowed_package_updated_at: latest_updated_at.to_i)
    end

    memoize def cache_key_without_rate_limit?
      GitHub.flipper[:site_scoped_installation_cache_key_without_rate_limit].enabled?(target)
    end

    def update_rate_limit(installation)
      return unless cache_key_without_rate_limit?
      return if installation.rate_limit == rate_limit

      GitHub.dogstats.increment("site_scoped_integration_installation.creator.rate_limit_changed")

      ActiveRecord::Base.connected_to(role: :writing) do
        installation.update!(rate_limit: rate_limit)
      end
    end

    def raise_error(e)
      raise ScopedIntegrationInstallation::Result::Error, e
    end
  end
end
