# typed: true
# frozen_string_literal: true

class Api::EnterpriseDependabotRepositoryAccess < Api::Enterprise::App
  get "/enterprises/:enterprise_id/dependabot/repository-access", operation_id: "dependabot/repository-access-for-enterprise" do
    enterprise = find_enterprise!

    control_access :read_enterprise_code_security_and_analysis_settings,
      resource: enterprise,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error! 404 unless enterprise.advanced_security_purchased?

    begin
      org_ids = enterprise.organization_ids
      accessible_repos = Repository.where(organization_id: org_ids).where(id: all_repository_access_ids(org_ids))
      paginated_repos = paginate_rel(accessible_repos)
      data = { repositories: paginated_repos, total_count: paginated_repos.total_entries }
      data[:default_level] = enterprise.dependabot_default_repository_access

      deliver :repository_access_hash, data
    rescue Dependabot::Twirp::ServiceUnavailableError => e
      Failbot.report(e)
      deliver_error!(503, message: "Dependabot service is temporarily unavailable")
    end
  end

  patch "/enterprises/:enterprise_id/dependabot/repository-access", operation_id: "dependabot/update-repository-access-for-enterprise", read_from_replicas: true do
    enterprise = find_enterprise!

    control_access :update_enterprise_code_security_and_analysis_settings_new_repos,
      resource: enterprise,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error! 404 unless enterprise.advanced_security_purchased?

    data = receive_with_openapi
    if !data.key?("repository_ids_to_add") && !data.key?("repository_ids_to_remove")
      deliver_error!(422, message: "Repositories to be added or removed must be passed in!")
    end

    repository_ids_to_add = Array(data["repository_ids_to_add"])

    org_ids = enterprise.organization_ids
    repositories = Repository.where(id: repository_ids_to_add, organization_id: org_ids)
    validate_repos_exist!(repository_ids_to_add, repositories)
    repos_by_org = repositories.where.not(public: true).group_by(&:organization_id)

    begin
      repos_by_org.each do |org_id, repos|
        org = Organization.find(org_id)
        repository_access_for(org).append(repository_ids: repos.map(&:id))
      end

      remove_ids = Array(data["repository_ids_to_remove"])
      if remove_ids.present?
        repos_to_remove = Repository.where(id: remove_ids, organization_id: org_ids)
        repos_to_remove.group_by(&:organization_id).each do |org_id, repos|
          org = Organization.find(org_id)
          repository_access_for(org).remove(repository_ids: repos.map(&:id))
        end
      end

      deliver_empty status: 204
    rescue Dependabot::Twirp::ServiceUnavailableError => e
      Failbot.report(e)
      deliver_error!(503, message: "Dependabot service is temporarily unavailable")
    end
  end

  put "/enterprises/:enterprise_id/dependabot/repository-access/default-level", operation_id: "dependabot/set-repository-access-default-level-for-enterprise", read_from_replicas: true do
    enterprise = find_enterprise!

    control_access :update_enterprise_code_security_and_analysis_settings_new_repos,
      resource: enterprise,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error! 404 unless enterprise.advanced_security_purchased?

    data = receive_with_openapi
    case data["default_level"]
    when "internal"
      enterprise.set_dependabot_default_repository_access("internal", actor: current_user)
    when "public"
      enterprise.clear_dependabot_default_repository_access(actor: current_user)
    end

    deliver_empty status: 204
  end

  private

  def validate_repos_exist!(repository_ids, repositories)
    return if repository_ids.blank?

    existing_repositories = repositories.pluck(:id)
    missing_ids = repository_ids - existing_repositories
    unless missing_ids.empty?
      deliver_error!(404, message: "Invalid repository IDs: #{missing_ids.join(', ')}")
    end
  end

  def repository_access_for(org)
    Dependabot::RepositoryAccess.for(org: org, actor: current_user)
  end

  def all_repository_access_ids(org_ids)
    org_ids.flat_map do |org_id|
      org = Organization.find(org_id)
      repository_access_for(org).list.pluck(:id)
    end
  end
end
