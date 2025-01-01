# typed: false
# frozen_string_literal: true

class Registry::PackagesController < AbstractRepositoryController

  before_action :check_packages_availability
  before_action :ensure_package_admin, only: [:restore, :options, :destroy]
  before_action :set_package, except: [:index, :commit]
  before_action :redirect_migrated_package, only: [:show]
  before_action :spammy_behaviour_check

  include Registry::QueryHelper

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    only: [:edit]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    only: [:versions]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Memex,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    only: [:options]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show, :edit, :options, :versions],
    optional: true

  PAGE_SIZE = 30

  layout "repository"

  def index
    # The only XHR request to hit this endpoint is when the user is searching within **the old repo packages page**.
    # URL like: http://github.localhost/monalisa/smile/packages
    # This endpoint is **not** used anymore when clicking the "Packages" sidebar on the repo page.
    # Clicking "Packages" in the sidebar leads to the org/user level package page.
    # URL like: http://github.localhost/monalisa?tab=packages&repo_name=smile
    #
    # Handling the empty state for no search results is done inside the `packages/filtered_packages` partial.
    # Handling the empty state for no repo packages existing is done inside the `packages/index` partial.
    if request.xhr? && !pjax?
      render partial: "registry/packages/filtered_packages", locals: {
        owner: current_repository.owner,
        packages: packages,
        params: params,
      }
    else
      render "registry/packages/index", locals: {
        packages: packages,
      }
    end
  end

  def show
    return render_404 if params[:version] == "docker-base-layer"

    if params[:version].present?
      versions = @package.package_versions
      versions = versions.not_deleted unless current_repository.adminable_by?(current_user)

      latest_version = versions.find_by_version(params[:version])
    else
      latest_version = @package.latest_version
    end

    versions = @package.package_versions.not_deleted.order(id: :desc).limit(5)

    view = create_view_model(
      Registry::Packages::ShowView,
      owner: current_repository.owner,
      repository: current_repository
    )
    render "registry/packages/show", locals: {
      package: @package,
      versions: versions,
      latest_version: latest_version,
      view: view,
    }
  end

  def edit
    version = @package.package_versions.find(params[:version_id])

    return render_404 unless @package.repository.writable_by?(current_user)

    view = create_view_model(
      Registry::Packages::ShowView,
      owner: current_repository.owner,
      repository: current_repository,
    )
    render "registry/packages/edit", locals: {
      package: @package,
      version: version,
      view: view,
    }
  end

  def commit # rubocop:todo GitHub/UseRestfulActions
    package_version = Registry::PackageVersion.find(params[:version_id])
    return render_404 unless package_version.package.repository.writable_by?(current_user)

    package_version.metadata.set(Registry::Metadatum::KEYS[:README], params[:package_version_body])
    return render_404 unless package_version.save

    flash[:notice] = "Package readme updated successfully."
    redirect_to package_path(current_repository.owner, current_repository.name, params[:id],
      version: package_version.version)
  end

  def versions # rubocop:todo GitHub/UseRestfulActions
    versions = if current_repository.adminable_by?(current_user) && params.dig(:filters, :versions) == "deleted"
      @package.package_versions.includes(:author).order(id: :desc).where.not(deleted_at: nil)
    else
      @package.package_versions.not_deleted.includes(:author).order(id: :desc)
    end

    view = create_view_model(
      Registry::Packages::ShowView,
      owner: current_repository.owner,
      repository: current_repository,
    )

    render "registry/packages/versions", locals: {
      package: @package,
      versions: versions.paginate(page: current_page, per_page: PAGE_SIZE),
      view: view,
    }
  end

  def destroy
    begin
      @package.delete!(actor: current_user)
    rescue Registry::Package::PackageDeletionError => e
      flash[:error] = e
      return redirect_to package_path
    end
    redirect_to packages_path
  end

  def restore # rubocop:todo GitHub/UseRestfulActions
    @package.restore!(actor: current_user)

    if current_repository.owner.organization?
      redirect_to settings_org_packages_path(
        organization_id: current_repository.owner.name,
        page: current_page,
        restored_package: @package.name,
        anchor: "deleted-packages"
      )
    else
      redirect_to settings_packages_path(
        page: current_page,
        restored_package: @package.name,
        anchor: "packages"
      )
    end
  rescue Registry::Package::PackageConflictError => e
    existing_package = Registry::Package.find_by(owner: @package.owner, name: @package.original_name)
    flash[:packages_error] = "Another package exists with the same name conflicting with the restore: #{ActionController::Base.helpers.link_to(@package.original_name, package_path(id: existing_package.id))}"
    if current_repository.owner.organization?
      redirect_to settings_org_packages_path(organization_id: current_repository.owner.name, page: current_page)
    else
      redirect_to settings_packages_path(page: current_page)
    end
  end

  def options # rubocop:todo GitHub/UseRestfulActions
    render "registry/packages/options", locals: { package: @package }
  end

  private

  def ensure_package_admin
    unless current_repository.adminable_by?(current_user)
      flash[:error] = "You do not have permissions to delete this package."
      redirect_to packages_path
    end
  end

  def set_package
    @package = Registry::Package.includes(:repository).find(params[:id])
    return render_404 unless @package.repository == current_repository
  end

  def query
    raw_query = params[:q]
    raw_query.strip if raw_query.is_a?(String)
  end

  def packages
    results, packages = packages_for_query(
      current_user: current_user,
      user_session: user_session,
      owner: current_repository.owner,
      repo_id: current_repository.id,
      query: query,
      package_type: ecosystem_param,
      visibility: visibility_param,
      sort: sort_param,
      page: current_page,
      per_page: PAGE_SIZE,
      use_cached_versions: true,
    )

    WillPaginate::Collection.create(current_page, PAGE_SIZE) do |pager|
      pager.replace(packages)
      pager.total_entries ||= results.total_entries
    end
  end

  def redirect_migrated_package
    if @package.migrated?
      owner_type = @package.owner.organization? ? "orgs" : "users"
      ecosystem = @package.package_type == "docker" ? "container" : @package.package_type
      name = @package.package_type == "docker" ? "#{@package.repository.name}/#{@package.name}" : "#{@package.name}"
      redirect_to packages_two_view_path(user_type: owner_type, user_id: @package.owner.display_login, ecosystem: ecosystem, name: name)
    end
  end

  def spammy_behaviour_check
    # @package is not set when navigated to repo packages list page. Eg : http://github.localhost/monalisa/testrepo/packages
    owner = @package.present? ? @package.owner : current_repository.owner
    render_404 if !PackageRegistryHelper.allow_access_to_actor?(owner, current_user)
  end

  def check_packages_availability
    render_404 unless PackageRegistryHelper.show_packages?
  end
end
