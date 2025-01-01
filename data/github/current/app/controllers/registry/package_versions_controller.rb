# typed: true
# frozen_string_literal: true

class Registry::PackageVersionsController < AbstractRepositoryController

  before_action :ensure_package_version_verification_matches, except: [:restore]
  before_action :ensure_package_admin
  before_action :spammy_behaviour_check

  def destroy
    begin
      package_version.delete!(
        actor: current_user,
        via_actions: false,
        user_agent: "web UI",
      )
    rescue Registry::PackageVersion::PublicVersionDeletionError
      flash[:error] = "Public packages cannot be deleted. Please contact support for assistance."
      return redirect_to all_versions_path
    rescue Registry::PackageVersion::PackageVersionDeletionError => e
      flash[:error] = e
      return redirect_to all_versions_path
    end

    flash[:package_version_deleted] = package_version.original_name || package_version.version
    redirect_to all_versions_path
  end

  def restore # rubocop:todo GitHub/UseRestfulActions
    package_version.restore!(actor: current_user)

    flash[:success] = "Package version has been restored."
    redirect_to all_versions_path(filters: { versions: "deleted" })
  rescue Registry::PackageVersion::PackageVersionConflictError => e
    flash[:error] = "Another package version exists with the same name conflicting with the restore."
    if current_repository.owner.organization?
      redirect_to all_versions_path(filters: { versions: "deleted" })
    else
      redirect_to all_versions_path(filters: { versions: "deleted" })
    end
  rescue Registry::PackageVersion::PackageVersionRestorationError => e
    flash[:error] = e.message
    redirect_to packages_path(current_repository.owner, current_repository)
  end

  private

  def ensure_package_version_verification_matches
    unless package_version.package.name.casecmp?(params[:verify])
      flash[:error] = "You must type the name of the package to confirm."
      redirect_to all_versions_path
    end
  end

  def ensure_package_admin
    unless current_repository.adminable_by?(current_user)
      flash[:error] = "You do not have permissions to delete this package."
      redirect_to all_versions_path
    end
  end

  def package_version # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @package_version ||= current_repository.packages.find(params[:package_id]).package_versions.find(params[:id])
  end

  def spammy_behaviour_check
    owner = package_version.package.owner
    render_404 if !PackageRegistryHelper.allow_access_to_actor?(owner, current_user)
  end

  def all_versions_path(**opts)
    package_versions_path(package_version.package.owner, package_version.package.repository, package_version.package.id, opts)
  end
end
