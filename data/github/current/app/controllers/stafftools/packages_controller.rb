# typed: true
# frozen_string_literal: true

class Stafftools::PackagesController < StafftoolsController

  before_action :ensure_user_exists

  layout "layouts/stafftools/repository/overview"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  def trigger_billing_reconciliation # rubocop:todo GitHub/UseRestfulActions
    user_id = this_user.id
    GitHub.logger.info(
      "code.function" => __method__,
      "code.namespace" => self.class.name,
      "gh.registry.owner_id" => user_id,
    )
    Packages::BillingStorageReconciliationJob.perform_later(user_id: user_id)

    flash[:notice] = "Successfully dispatched billing reconciliation job. It might take some time for results to show."
    redirect_to stafftools_user_packages_path(this_user)
  end

  def trigger_docker_storage_reset # rubocop:todo GitHub/UseRestfulActions
    owner_id = this_user.id
    GitHub.logger.info(
      "code.function" => __method__,
      "code.namespace" => self.class.name,
      "gh.registry.owner_id" => owner_id,
    )
    Packages::DockerMigrationResetBillingOwnerJob.perform_later(owner_id: owner_id)

    flash[:notice] = "Successfully dispatched Docker storage reset job. It might take some time for results to show."
    redirect_to stafftools_user_packages_path(this_user)
  end

  def trigger_packages_migration # rubocop:todo GitHub/UseRestfulActions
    login = this_user.login
    package_type = params.require(:package_type)
    force = params.require(:force)
    retry_failed = params.fetch(:retry_failed, false)
    GitHub.logger.info(
      "code.function" => __method__,
      "code.namespace" => self.class.name,
      "gh.registry.display_login" => login,
      "gh.registry.force" => force,
      "gh.registry.retry_failed" => retry_failed,
      "gh.registry.package_type" => package_type
    )
    Packages::Migration::MigrateNamespaceJob.perform_later(login, package_type, force: force == "true", retry_failed: retry_failed == "true")

    flash[:notice] = "Successfully dispatched v1 #{package_type} migration job. It might take some time for results to show."
    redirect_to stafftools_user_packages_path(this_user)
  end

  def delete_version # rubocop:todo GitHub/UseRestfulActions
    repo_name, package_id, package_version = delete_package_version_params

    repo = this_user.repositories.find_by!(name: repo_name)
    package = repo.packages.find(package_id)
    version = package.package_versions.find_by!(version: package_version)
    version.delete!(force_delete: true)

    redirect_to stafftools_user_packages_path(this_user)
  end

  def purge_deleted # rubocop:todo GitHub/UseRestfulActions
    repo_name, package_id = delete_package_params

    repo = this_user.repositories.find_by!(name: repo_name)
    package = repo.packages.find(package_id)
    package.delete

    redirect_to stafftools_user_packages_path(this_user)
  end

  def delete_for_repo # rubocop:todo GitHub/UseRestfulActions
    repo_name = delete_for_repo_params

    repository = this_user.repositories.find_by!(name: repo_name)
    Packages::DeletePackagesForRepositoryJob.perform_later(repository_id: repository.id)

    flash[:notice] = "Successfully dispatched packages delete job for repository #{repository.name}. The deletion will happen in the background so it make take some time for the results to show up."
    redirect_to stafftools_user_packages_path(this_user)
  end

  def index
    page = params.fetch(:page) { 1 }
    per_page = params.fetch(:per_page) { 300 }

    packages = paginate_packages(this_user, per_page, page)
    org_metadata = org_metadata(this_user)

    repository_ids = packages.map(&:repository_id).uniq
    repositories_packages_data = grouped_repository_packages_data(packages, repository_ids)
    repositories_packages_count = total_package_counts(repository_ids)
    repositories_unmigrated_packages_count = total_unmigrated_package_counts(repository_ids)
    migrated_packages_count = repositories_packages_count - repositories_unmigrated_packages_count

    render "stafftools/packages/index",
           layout: "layouts/stafftools/organization/content",
           locals: {
             owner: this_user,
             packages: packages,
             total_packages_count: repositories_packages_count,
             migrated_count: migrated_packages_count,
             repositories_packages_data: repositories_packages_data,
             org_metadata: org_metadata,
           }
  end

  private

  def paginate_packages(user, per_page, page)
    user
      .packages
      .unmigrated
      .includes(:repository)
      .order("repository_id ASC")
      .paginate(page: page, per_page: per_page)
  end

  def org_metadata(org)
    metadata = Hash.new
    metadata["account_type"] = org.type
    metadata["account_name"] = org.name
    return metadata unless org.type == "Organization"
    metadata["members_can_publish_private_packages"] = org.members_can_publish_private_packages?
    metadata["members_can_publish_internal_packages"] = org.members_can_publish_internal_packages?
    metadata["members_can_publish_public_packages"] = org.members_can_publish_public_packages?
    metadata["packages_can_inherit_access_from_repo"] = org.packages_can_inherit_access_from_repo?
    metadata
  end

  def grouped_repository_packages_data(packages, repository_ids)
    package_ids = packages.map(&:id)
    grouped_packages = packages.group_by { |package| package.repository }

    grouped_repository_package_counts = grouped_repository_package_counts(repository_ids)
    grouped_repository_unmigrated_package_counts = grouped_repository_unmigrated_package_counts(repository_ids)
    package_version_counts = grouped_package_version_counts(package_ids)
    package_download_counts = grouped_package_download_counts(package_ids)
    package_latest_versions = grouped_latest_versions(package_ids)

    grouped_packages.map do |(repository, group_packages)|
      packages_count = grouped_repository_package_counts.fetch(repository.id) { 0 }
      unmigrated_count = grouped_repository_unmigrated_package_counts.fetch(repository.id) { 0 }
      {
        repository: repository,
        packages_count: packages_count,
        hidden_count: packages_count - unmigrated_count,
        packages: grouped_package_data(group_packages, package_version_counts, package_download_counts, package_latest_versions),
      }
    end
  end

  def grouped_package_data(packages, package_version_counts, package_download_counts, package_latest_versions)
    packages.map do |package|
      {
        package: package,
        version_count: package_version_counts.fetch(package.id) { 0 },
        download_count: package_download_counts.fetch(package.id) { 0 },
        latest_version: package_latest_versions[package.id],
      }
    end
  end

  def total_unmigrated_package_counts(repository_ids)
    ::Registry::Package
      .unmigrated
      .where(repository_id: repository_ids)
      .count(:id)
  end

  def total_package_counts(repository_ids)
    ::Registry::Package
      .where(repository_id: repository_ids)
      .count(:id)
  end

  def grouped_repository_package_counts(repository_ids)
    ::Registry::Package
      .where(repository_id: repository_ids)
      .group(:repository_id)
      .count(:id)
  end

  def grouped_repository_unmigrated_package_counts(repository_ids)
    ::Registry::Package
      .unmigrated
      .where(repository_id: repository_ids)
      .group(:repository_id)
      .count(:id)
  end

  def grouped_package_version_counts(package_ids)
    ::Registry::PackageVersion
      .from("package_versions FORCE INDEX (index_package_versions_on_package_id_deleted_at_and_such)")
      .where(registry_package_id: package_ids)
      .not_deleted
      .group(:registry_package_id)
      .count(:id)
  end

  def grouped_package_download_counts(package_ids)
    ::Registry::Package
      .not_deleted
      .where(id: package_ids)
      .joins(:downloads)
      .group(:id)
      .sum("package_download_activities.package_download_count")
  end

  def grouped_latest_versions(package_ids)
    latest_versions_by_date = ::Registry::PackageVersion
      .not_deleted
      .select(:id, :registry_package_id, :version, :created_at, :updated_at)
      .where(
        registry_package_id: package_ids,
        updated_at: ::Registry::PackageVersion.not_deleted.select("MAX(updated_at)").where(registry_package_id: package_ids).group(:registry_package_id),
      )
      .order(updated_at: :DESC)

    latest_versions_by_tag = ::Registry::PackageVersion
      .not_deleted
      .select(:id, :registry_package_id, :version, :created_at, :updated_at)
      .joins(:tags)
      .where(registry_package_id: package_ids)
      .where.not(version: "docker-base-layer")
      .where("registry_package_tags.name = 'latest'")
      .order("registry_package_tags.id DESC")

    latest_versions_by_date_group = latest_versions_by_date.group_by(&:registry_package_id)
    latest_versions_by_tag_group = latest_versions_by_tag.group_by(&:registry_package_id)
    latest_versions_hash = latest_versions_by_date_group.merge(latest_versions_by_tag_group)

    latest_versions_hash.each_with_object({}) { |(package_id, versions), hash| hash[package_id] = versions.first }
  end

  def delete_for_repo_params
    params.require(:repo_name)
  end

  def delete_package_params
    params.require([:repo_name, :package_id])
  end

  def delete_package_version_params
    params.require([:repo_name, :package_id, :package_version])
  end

  def delete_packages_for_repo_params
    params.require(:repo_name)
  end

end
