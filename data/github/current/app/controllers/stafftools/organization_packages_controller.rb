# typed: true
# frozen_string_literal: true

class Stafftools::OrganizationPackagesController < StafftoolsController # rubocop:todo GitHub/ControllersShouldHaveTests
  include RegistryTwo::MembersHelper
  before_action :ensure_user_exists
  helper_method :members_map, :repos_with_actions_access

  layout "layouts/stafftools/repository/overview"

  RMS_ERROR = "Unable to retrieve data from RMS, V2 data will be incomplete or missing."
  ACTIONS_INTEGRATION_ERROR = "Unable to fetch Actions Integration, actions repo access lists will be incomplete or missing."

  def index
    page = params.fetch(:page) { 1 }
    per_page = params.fetch(:per_page) { 20 }

    package_page = paginate_packages(this_user, per_page, page)
    repositories_packages_data = grouped_repository_packages_data(package_page)
    org_metadata = org_metadata(this_user)

    render "stafftools/organization_packages/index",
    layout: "layouts/stafftools/organization/content",
    locals: {
      owner: this_user,
      packages: package_page,
      repositories_packages_data: repositories_packages_data,
      org_metadata: org_metadata,
    }
  end

  def purge_deleted # rubocop:todo GitHub/UseRestfulActions
    begin
      ecosystem, namespace, name = delete_package_params
      client.delete_package(ecosystem: ecosystem, namespace: namespace, name: name, actor: this_user, staff_override: true)
    rescue ActionController::ParameterMissing => e
      flash[:error] = "Failed to delete package. There was an issue with the provided parameters: #{e.message}"
    rescue PackageRegistry::Twirp::BaseError
      flash[:error] = "Failed to delete package. Had trouble communicating with RMS."
    end
    redirect_to stafftools_user_organization_packages_path(this_user)
  end

  private

  def client # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @client ||= PackageRegistry::Twirp.metadata_client
  end

  def paginate_packages(user, per_page, page)
    begin
      get_all_packages_resp = client.get_all_package_summaries(namespace: this_user.name, limit: per_page, offset: (page.to_i - 1) * per_page, filter: :REPO_ID, order: :DESCENDING, exclude_deleted: true, full_response: true)
    rescue PackageRegistry::Twirp::BaseError
      flash[:error] = RMS_ERROR
      return []
    end

    pagination_results = WillPaginate::Collection.create(page, per_page) do |pager|
      pager.replace(get_all_packages_resp[:package_summaries])
      pager.total_entries ||= get_all_packages_resp[:total_packages]
    end
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

  def grouped_repository_packages_data(package_summaries)
    repository_ids = package_summaries.map { |summary| summary&.package&.repo_id }.uniq
    # Repo ID = 0 means that the package is not attached to repository
    existing_repositories = get_repositories_by_id(repository_ids.select { |id| id > 0 })
    packages_counts = grouped_repository_package_counts(existing_repositories)

    grouped_packages = package_summaries.group_by { |package_summary| package_summary&.package&.repo_id }

    if grouped_packages.key?(0) && grouped_packages.length > 1
      grouped_packages[0] = grouped_packages.delete(0)
    end

    grouped_packages.map do |(repository_id, group_package_summaries)|
      {
        repository: existing_repositories[repository_id],
        packages_count: packages_counts.fetch(repository_id) { 0 },
        packages: grouped_package_data(group_package_summaries),
      }
    end
  end

  def grouped_package_data(group_package_summaries)
    group_package_summaries.map do |package_summary|
      {
        package: package_summary&.package,
        latest_version: package_summary&.latest_version,
        version_count:  package_summary&.total_version_count,
        download_count: package_summary&.total_download_count,
      }
    end
  end

  def grouped_repository_package_counts(repositories)
    results = {}
    repo_package_counts = repositories.each do |repo_id, _repo|
      begin
        unless repo_id == 0
          repo_packages_resp = client.get_packages_by_repo(repo_id: repo_id)
          undeleted_packages = repo_packages_resp&.packages&.select { |package| package.deleted_at.nil? }
          results[repo_id] = undeleted_packages&.length { 0 }
        end
      rescue PackageRegistry::Twirp::BaseError
        flash[:error] = RMS_ERROR
        results[repo_id] = 0
      end
    end
    results
  end

  def get_repositories_by_id(repository_ids)
    filtered_repositories = {}
    repositories = this_user
      .repositories.each do |repository|
        if repository_ids.include? repository.id
          filtered_repositories[repository.id] = repository
        end
      end
    filtered_repositories
  end

  def members_map(package_id)
    return @members_map if defined?(@member_map)

    package_roles = Role.system_package_roles.to_a
    package_admin_role = package_roles.select { |r| r.name == "package_admin" }

    @members_map = UserRole.where(role_id: package_roles.map(&:id))
                                .where(target_type: "Package", target_id: package_id)
                                .includes(:actor)
                                .select { |ur| ur.actor.present? }
                                .map { |ur| [ur.actor, ur.role] }
    @members_map.to_h
  end

  def repos_with_actions_access(package_id)
    integration = Apps::Internal.integration(:actions)
    if integration.blank?
      flash[:error] = ACTIONS_INTEGRATION_ERROR
      return {}
    end

    IntegrationAllowedPackage.joins(:repository).where(package_id: package_id, integration_id: integration.id, repositories: { active: true })
  end

  def delete_package_params
    params.require([:ecosystem, :namespace, :name])
  end

end
