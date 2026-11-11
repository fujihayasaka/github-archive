# typed: true
# frozen_string_literal: true

class Api::OrganizationDependabotRepositoryAccess < Api::App
  get "/organizations/:organization_id/dependabot/repository-access", operation_id: "dependabot/repository-access-for-org" do
    org = find_org!
    deliver_error! 404 unless org.dependabot_installed?

    control_access :read_org_security_products,
      resource: org,
      organization: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    begin
      accessible_repos = repository_access_for(org).list
      paginated_repos = paginate_rel(accessible_repos)
      data = { repositories: paginated_repos, total_count: paginated_repos.total_entries }

      if org.advanced_security_purchased?
        data[:default_level] = org.dependabot_default_repository_access
      end

      deliver :repository_access_hash, data
    rescue Dependabot::Twirp::ServiceUnavailableError => e
      Failbot.report(e)
      deliver_error!(503, message: "Dependabot service is temporarily unavailable")
    end
  end

  patch "/organizations/:organization_id/dependabot/repository-access", operation_id: "dependabot/update-repository-access-for-org" do
    org = find_org!
    deliver_error! 404 unless org.dependabot_installed?

    control_access :manage_org_security_products,
      resource: org,
      organization: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    data = receive_with_openapi
    if !data.key?("repository_ids_to_add") && !data.key?("repository_ids_to_remove")
      deliver_error!(422, message: "Repositories to be added or removed must be passed in!")
    end

    repository_ids_to_add = Array(data["repository_ids_to_add"])
    repository_ids_to_remove = Array(data["repository_ids_to_remove"])

    repositories = Repository.where(id: repository_ids_to_add, organization_id: org.id)
    validate_repos_exist!(repository_ids_to_add, repositories)
    repository_ids_to_add = repositories.where.not(public: true).pluck(:id)

    begin
      repository_access_for(org).append(repository_ids: repository_ids_to_add)
      repository_access_for(org).remove(repository_ids: repository_ids_to_remove)

      deliver_empty status: 204
    rescue Dependabot::Twirp::ServiceUnavailableError => e
      Failbot.report(e)
      deliver_error!(503, message: "Dependabot service is temporarily unavailable")
    end
  end

  put "/organizations/:organization_id/dependabot/repository-access/default-level", operation_id: "dependabot/set-repository-access-default-level" do
    org = find_org!
    deliver_error! 404 unless org.dependabot_installed?
    deliver_error! 404 unless org.advanced_security_purchased?

    control_access :manage_org_security_products,
      resource: org,
      organization: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    data = receive_with_openapi
    case data["default_level"]
    when "internal"
      org.set_dependabot_default_repository_access("internal", actor: current_user)
    when "public"
      org.clear_dependabot_default_repository_access(actor: current_user)
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
end
