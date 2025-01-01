# typed: false
# frozen_string_literal: true

class RegistryTwo::PackageVersionsController < RegistryTwo::Controller
  include PackageRegistry
  include Registry::PackageDownloadStatsService

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    ApplicationRecord::Iam,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  VERSIONS_PAGE_LIMIT = 50

  before_action :redirect_legacy_packages
  before_action :ensure_supported_ecosystem
  before_action :ensure_v2_ui_enabled
  before_action :get_active_versions_and_count, only: :show
  before_action :get_deleted_versions_count, only: :show
  before_action :ensure_package, only: :reclaimed_storage_version
  before_action :spammy_behaviour_check
  before_action :ensure_package_admin, only: :restore
  before_action only: [:show] do
    repo_scoped_redirect(:repo_package_versions_two_path)
  end
  skip_before_action :cap_pagination

  def show
    versions = if package_admin? && (params.dig(:filters, :versions) == "deleted")
      # Fetch deleted package versions for current pagination page only.
      resp = deleted_package_versions(version_limit: VERSIONS_PAGE_LIMIT, version_offset: (current_page - 1) * VERSIONS_PAGE_LIMIT)
      if resp.success?
        Array.wrap(resp.package_versions)
      else
        # At this point we already called `render` or `redirect` inside `deleted_package_versions` so we just need to return.
        return
      end
    else
      @active_metadata.package_versions
    end

    total_entries = if versions_filter == "deleted"
      @deleted_versions_count
    else
      @active_versions_count
    end

    render "registry_two/package_versions/show", locals: {
      package: @active_metadata.package,
      package_versions: versions,
      paginated_package_versions: versions.paginate(page: params[:page], per_page: VERSIONS_PAGE_LIMIT, total_entries: total_entries),
      viewer_is_admin: package_admin?,
      # Displayed to any user viewing the active versions of a container package.
      tagged_count: @active_metadata.total_tagged_versions_count,
      # Displayed to any user viewing the active versions of a container package.
      untagged_count: @active_metadata.total_untagged_versions_count,
      # Displayed to any user viewing active or deleted versions of non container packages.
      active_count: @active_metadata.total_version_count,
      # Displayed to admin users viewing active or deleted versions of non container packages.
      deleted_count: @deleted_versions_count,
      version_type_filter: version_type_filter,
      versions_filter: versions_filter,
      viewer_can_read_repo: current_user_can_read_repo?,
      user_type: params[:user_type] || get_owner_type,
      is_actions_package: package.is_actions_package?
    }
  end

  def reclaimed_storage_version # rubocop:todo GitHub/UseRestfulActions
    render_404 unless request.xhr?
    render_404 if package_admin? && params.dig(:filters, :versions) == "deleted"

    render partial: "registry_two/package_versions/reclaimed_storage_version",
      locals: {
        package:,
        show_reclaimed_storage: show_reclaimed_storage?,
        package_version: params[:version],
      }
  end

  def restore # rubocop:todo GitHub/UseRestfulActions
    begin
      name, ecosystem, version = params.require([:name, :ecosystem, :version])
      client.restore_package_version(namespace: owner.display_login, name: name, ecosystem: ecosystem, actor: current_user, version: version)
    rescue PackageRegistry::Twirp::BaseError, ActionController::ParameterMissing => e
      GitHub.logger.error(e)
      flash[:error] = "Couldn't restore this package version."
      return redirect_to :back
    end

    flash[:success] = "Package version has been restored."
    redirect_to package_versions_two_path(filters: { versions: "deleted" })
  end

  def delete_package_version # rubocop:todo GitHub/UseRestfulActions
    if package.is_actions_package?
      name_with_version = "#{package.name}@#{params[:tag]}"
      unless name_with_version.casecmp?(params[:verify])
        flash[:error] = "You must type the name and version of the package to confirm."
        return redirect_to package_versions_two_path
      end
    else
      unless params[:name].casecmp?(params[:verify])
        flash[:error] = "You must type the name of the package to confirm."
        return redirect_to package_versions_two_path
      end
    end

    if package.is_actions_package?
      # verify download count as past a certain amount we don't allow deletion
      download_counts = if !GitHub.enterprise? || PackageRegistryHelper.ghes_registry_v2_enabled?
        client.get_package_version_download_counts(
          package_id: package.id,
          version_id: params[:version].to_i
        )
      else
        PackageRegistry::DownloadCounts::NULL
      end

      total_download_count = download_counts.total
      if total_download_count > MAX_DOWNLOAD_COUNT_BEFORE_DELETE_RESTRICTION_FOR_IMMUTABLE_ACTIONS
        flash[:error] = "Unable to delete a package version once there are more than #{MAX_DOWNLOAD_COUNT_BEFORE_DELETE_RESTRICTION_FOR_IMMUTABLE_ACTIONS} downloads"
        return redirect_to package_versions_two_path
      end
    end

    begin
      client.delete_package_version(
        ecosystem: package.package_type,
        namespace: package.namespace,
        name: package.name,
        actor: current_user,
        mode: :soft,
        version: params[:version],
      )
    rescue PackageRegistry::Twirp::FailedPreconditionError => e
      flash[:error] = e.msg.humanize
      return redirect_to package_versions_two_path
    rescue PackageRegistry::Twirp::BaseError
      flash[:error] = "The package version could not be deleted. Please try again later."
      return redirect_to package_versions_two_path
    end

    redirect_to package_versions_two_path
  end

  private

  def redirect_legacy_packages
    redirect_to package_versions_path(owner, package.repository, package.id) if LEGACY_ECOSYSTEMS.include?(params[:ecosystem])
  end

  # Count of all deleted versions. RMS does not include untagged versions in this count.
  def total_deleted_versions_count(ecosystem, deleted_metadata)
    return 0 unless deleted_metadata

    if ecosystem == "container"
      # TODO: Find a way to include the untagged versions which we don't get from RMS!
    end

    deleted_metadata.total_version_count
  end

  # Count of all active versions independent of any filters selected.
  def total_active_versions_count(ecosystem, active_metadata)
    return 0 unless active_metadata

    if ecosystem == "container"
      # We might had a filter selected when we fetched these counts so we need to add the counts of both tagged and untagged versions.
      # We can't use `total_version_count` since that reflected the already filtered count.
      active_metadata.total_tagged_versions_count + active_metadata.total_untagged_versions_count
    else
      active_metadata.total_version_count
    end
  end

  # Count of active versions for current filter selection.
  # For non container registry packages there are no special filters on active versions.
  # So this means we will just return `total_version_count`.
  # For container registry packages, we have two filters: `tagged` and `untagged`.
  # Using one of those filters will cause the `total_version_count` to reflect the nr of versions for that filter.
  def filtered_active_version_count(ecosystem, active_metadata, version_type_filter)
    return 0 unless active_metadata

    if ecosystem == "container" && version_type_filter != "all"
      if version_type_filter == "tagged"
        active_metadata.total_tagged_versions_count
      else
        active_metadata.total_untagged_versions_count
      end
    else
      active_metadata.total_version_count
    end
  end

  def get_active_versions_and_count
    begin
      @active_metadata = client.get_package_metadata(
        ecosystem: params[:ecosystem],
        namespace: owner.display_login,
        name: params[:name],
        actor: current_user,
        # Unlike `get_deleted_versions_count`, we actually fetch the package versions for the current pagination params here.
        # Note that RMS internaly has a max and default limit of 100 versions.
        version_limit: VERSIONS_PAGE_LIMIT,
        version_offset: (current_page - 1) * VERSIONS_PAGE_LIMIT,
        version_filter: version_type_filter,
        include_download_count: true
      )

      @active_versions_count = filtered_active_version_count(params[:ecosystem], @active_metadata, version_type_filter)
      no_active_version_present = total_active_versions_count(params[:ecosystem], @active_metadata).zero?

      GitHub.logger.info(
        "Fetched get_active_versions_and_count from RMS",
        "code.namespace" => "RegistryTwo::PackageVersionsController",
        "code.function" => "get_active_versions_and_count",
        "gh.registry.version_limit" => VERSIONS_PAGE_LIMIT,
        "gh.registry.version_offset" => (current_page - 1) * VERSIONS_PAGE_LIMIT,
        "gh.registry.metadata.total_version_count" => @active_versions_count,
      )

      # We need to explicitly pass `user_type` since it's not always present in the params.
      # This is because this controller is used for multiple routes.
      # One route does contain the `user_type` in form of `users` or `orgs`.
      # The other route does not contain this.
      # The route without `user_type` is used when a package is linked to a repo (maybe also in other cases).
      # The route with `user_type` is used "normally".
      redirect_to packages_two_path(user_type: params[:user_type] || get_owner_type) if no_active_version_present
    rescue PackageRegistry::Twirp::ServiceUnavailableError => e
      GitHub.logger.error(e)
      render "registry_two/packages/service_unavailable"
    rescue PackageRegistry::Twirp::BaseError => e
      GitHub.logger.error(e)
      render_404
    end
  end

  def get_deleted_versions_count
    deleted_metadata = client.get_deleted_package_versions(
      namespace: package.namespace,
      name: package.name,
      ecosystem: package.package_type,
      actor: current_user,
      # We only need the overview data containing the counts, therefore we can just fetch one version.
      version_limit: 1,
      version_offset: 0,
    )

    @deleted_versions_count = total_deleted_versions_count(params[:ecosystem], deleted_metadata)

    GitHub.logger.info(
      "Fetched get_deleted_versions_count from RMS",
      "code.namespace" => "RegistryTwo::PackageVersionsController",
      "code.function" => "get_deleted_versions_count",
      "gh.registry.version_limit" => 1,
      "gh.registry.version_offset" => 0,
      "gh.registry.metadata.total_version_count" => @deleted_versions_count,
    )
  rescue PackageRegistry::Twirp::ServiceUnavailableError => e
    GitHub.logger.error(e)
    render "registry_two/packages/service_unavailable"
  rescue PackageRegistry::Twirp::BaseError => e
    GitHub.logger.error(e)
    render_404
  end

  # Similar to `get_active_versions_and_count` but designed to be used outside of rails hooks.
  # This won't modify the global state but rather return the fetched versions.
  # The caller needs to ensure that if we return `nil`, we return from the controller
  # action to prevent double render errors from happening.
  def deleted_package_versions(version_limit:, version_offset:)
    deleted_metadata = client.get_deleted_package_versions(
      namespace: package.namespace,
      name: package.name,
      ecosystem: package.package_type,
      actor: current_user,
      version_limit: version_limit,
      version_offset: version_offset
    )

    GitHub.logger.info(
      "Fetched deleted_package_versions from RMS",
      "code.namespace" => "RegistryTwo::PackageVersionsController",
      "code.function" => "deleted_package_versions",
      "gh.registry.version_limit" => version_limit,
      "gh.registry.version_offset" => version_offset,
      "gh.registry.metadata.total_version_count" => deleted_metadata&.total_version_count || 0,
    )

    GetDeletedPackageVersionsResponse.new(deleted_metadata&.package_versions, failure: false)
  rescue PackageRegistry::Twirp::ServiceUnavailableError => e
    GitHub.logger.error(e)
    render "registry_two/packages/service_unavailable"

    GetDeletedPackageVersionsResponse.new(nil, failure: true)
  rescue PackageRegistry::Twirp::BaseError => e
    GitHub.logger.error(e)
    render_404

    GetDeletedPackageVersionsResponse.new(nil, failure: true)
  end

  # Helper class to distinguish between no data received or an actual error when talking to RMS.
  # When fetching the active versions, `metadata.total_version_count` will even be populated when there are no
  # `metadata.package_versions`(no package versions for the passed pagination params).
  # `deleted_package_versions` and `get_deleted_versions_count` on the other hand will return `nil` if there are no deleted versions for the passed pagination params.
  # This helper is therefore not needed for `get_active_versions_and_count`.
  # But also not for `get_deleted_versions_count` since that one is only used for a rails hooks.
  # Rails hooks don't need an explicit `return` since any calls to `render` or
  # `redirect` will automatically return and prevent the controller action from running.
  class GetDeletedPackageVersionsResponse
    def initialize(package_versions, failure:)
      @package_versions = package_versions
      @failure = failure
    end

    def package_versions
      @package_versions
    end

    def success?
      !@failure
    end
  end

  def current_repository
    return nil unless current_user_can_read_repo?
    @active_metadata&.package&.repository
  end

  def current_user_can_read_repo?
    @active_metadata&.package&.repository&.readable_by?(current_user)
  end

  def version_type_filter
    if %w[all tagged untagged].include?(params.dig(:filters, :version_type))
      params.dig(:filters, :version_type).to_s
    else
      "all"
    end
  end

  def versions_filter
    if %w[active deleted].include?(params.dig(:filters, :versions))
      params.dig(:filters, :versions).to_s
    else
      "active"
    end
  end
end
