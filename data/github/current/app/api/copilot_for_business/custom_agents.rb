# typed: true
# frozen_string_literal: true

class Api::CopilotForBusiness::CustomAgents < Api::App
  include FeatureFlagHelper
  include ReceiveSchemaWithOpenApi

  SOURCE_REPO_NAME = ".github-private"

  get "/enterprises/:enterprise_id/copilot/custom-agents/source", operation_id: "copilot/get-copilot-custom-agents-source-for-enterprise", read_from_replicas: true do

    enterprise = find_enterprise!

    ensure_endpoint_enabled!(enterprise)

    control_access :standard_authorization,
      resource: enterprise,
      permission: :read_enterprise_ai_controls,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: Copilot::ENTERPRISE_ADMIN_INSUFFICIENT_PERMISSIONS_MESSAGE

    source_repo_id = enterprise.subagent_definitions_source_repository_id

    if source_repo_id.blank?

      response = {
        organization: nil,
        repository: nil,
      }

      return deliver_raw(response, status: 200)
    end

    repository = Repositories::Public.find_active(source_repo_id)
    deliver_error! 404, message: "Configured source repository not found" if repository.blank?

    organization = find_org_in_enterprise!(enterprise, repository.owner_id)

    response = {
      organization: {
        id: organization.id,
        login: organization.display_login,
      },
      repository: {
        id: repository.id,
        name: repository.name,
        full_name: repository.name_with_owner_for_api,
      },
    }

    deliver_raw(response, status: 200)
  end

  put "/enterprises/:enterprise_id/copilot/custom-agents/source", operation_id: "copilot/set-copilot-custom-agents-source-for-enterprise", read_from_replicas: true do
    enterprise = find_enterprise!

    ensure_endpoint_enabled!(enterprise)

    control_access :standard_authorization,
      resource: enterprise,
      permission: :write_enterprise_ai_controls,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: Copilot::ENTERPRISE_ADMIN_INSUFFICIENT_PERMISSIONS_MESSAGE

    data = receive_with_openapi
    organization_id = data["organization_id"]

    deliver_error!(422, message: "organization_id is required") unless organization_id.present?

    # Find the organization in the enterprise
    org = find_org_in_enterprise!(enterprise, organization_id)

    # Find the .github-private repository in the organization
    source_repo = find_source_repo!(org)

    # Set the source repository
    with_write(clusters: [ApplicationRecord::Configurations]) do
      enterprise.set_subagent_definitions_source_repository_id(actor: current_user, repo_id: source_repo.id)
    end

    # Create ruleset by default unless opted out
    create_ruleset = data.fetch("create_ruleset", true)
    ruleset_data = T.let(nil, T.nilable(T::Hash[Symbol, T.untyped]))

    if create_ruleset
      begin
        with_write(clusters: [ApplicationRecord::Repositories]) do
          ruleset = SubAgentHandler.create_sub_agent_ruleset(enterprise)
          ruleset_data = {
            id: ruleset.id,
            name: ruleset.name,
            enforcement: ruleset.enforcement,
          }
        end
      rescue ArgumentError
        # Ruleset already exists - find and return it
        ruleset = SubAgentHandler.find_subagent_ruleset(enterprise)
        if ruleset
          ruleset_data = {
            id: ruleset.id,
            name: ruleset.name,
            enforcement: ruleset.enforcement,
          }
        end
      end
    end

    response = {
      organization: {
        id: org.id,
        login: org.display_login,
        avatar_url: org.primary_avatar_url,
      },
      repository: {
        id: source_repo.id,
        name: source_repo.name,
        full_name: source_repo.name_with_owner_for_api,
      },
    }

    response[:ruleset] = ruleset_data if ruleset_data.present?

    deliver_raw(response, status: 200)
  end

  delete "/enterprises/:enterprise_id/copilot/custom-agents/source", operation_id: "copilot/delete-copilot-custom-agents-source-for-enterprise", read_from_replicas: true do
    enterprise = find_enterprise!

    ensure_endpoint_enabled!(enterprise)

    control_access :standard_authorization,
      resource: enterprise,
      permission: :write_enterprise_ai_controls,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: Copilot::ENTERPRISE_ADMIN_INSUFFICIENT_PERMISSIONS_MESSAGE

    # Remove the source repository configuration
    with_write(clusters: [ApplicationRecord::Configurations]) do
      enterprise.unset_subagent_definitions_source_repository_id(actor: current_user)
    end

    deliver_raw({}, status: 204)
  end

  get "/enterprises/:enterprise_id/copilot/custom-agents", operation_id: "copilot/get-copilot-custom-agents-for-enterprise", read_from_replicas: true do

    enterprise = find_enterprise!

    ensure_endpoint_enabled!(enterprise)

    control_access :standard_authorization,
      resource: enterprise,
      permission: :read_enterprise_ai_controls,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: Copilot::ENTERPRISE_ADMIN_INSUFFICIENT_PERMISSIONS_MESSAGE

    source_repo_id = enterprise.subagent_definitions_source_repository_id

    if source_repo_id.blank?
      response = { custom_agents: nil }

      return deliver_raw(response, status: 200)
    end

    repository = Repositories::Public.find_active(source_repo_id)
    deliver_error! 404, message: "Configured source repository not found" if repository.blank?

    custom_agents = fetch_custom_agents!(repository, enterprise)

    custom_agents.sort_by! { |agent| agent[:name] }

    paginated_custom_agents = paginate_rel(custom_agents)

    if paginated_custom_agents.respond_to?(:total_pages)
      set_pagination_headers(paginated_custom_agents)
    end

    response = { custom_agents: paginated_custom_agents.to_a }

    deliver_raw(response, status: 200)
  end

  private

  def ensure_endpoint_enabled!(enterprise)
    deliver_error!(404, documentation_url: "#{GitHub::Config::DOCS_BASE_URL}/rest") unless enterprise.feature_flag_enabled?(:enterprise_ai_controls, default: false)
  end

  def find_org_in_enterprise!(enterprise, organization_id)
    org = enterprise.organizations.find_by(id: organization_id.to_i)
    deliver_error!(422, message: "Organization not found in this enterprise") unless org.present?

    org
  end

  def find_source_repo!(org)
    repo = org.repositories.find_by(name: SOURCE_REPO_NAME)
    deliver_error!(422, message: "Organization must have a #{SOURCE_REPO_NAME} repository") unless repo.present?

    repo
  end

  def fetch_custom_agents!(repository, enterprise)
    custom_agents = []

    default_branch_name = repository.default_branch
    return custom_agents if default_branch_name.blank?

    default_branch = repository.heads.find(default_branch_name)
    return custom_agents if default_branch.nil?

    oid = default_branch.target_oid
    return custom_agents unless GitRPC::Util.valid_full_oid?(oid)

    owner = T.must(repository.owner)

    # Custom agents are in /agents/*.md
    begin
      _, entries, _ = repository.tree_entries(oid, "agents", recursive: false)

      if entries.empty?
        return custom_agents
      end

      entries.each do |entry|
        next if entry.directory?
        next unless entry.name.end_with?(".md")

        agent_name = entry.name.gsub(/\.md\z/, "").titleize
        agent_file_path = "agents/#{entry.name}"

        custom_agents << {
          name: agent_name,
          file_path: agent_file_path,
          url: UrlHelpers.blob_url(
            user_id: owner,
            repository: repository,
            name: default_branch_name,
            path: agent_file_path,
            host: GitHub.host_name_with_tenant,
            protocol: GitHub.scheme
          ),
        }
      end
    rescue GitRPC::InvalidObject, GitRPC::NoSuchPath => e
      GitHub.logger.info(
        "Custom agents directory not found or inaccessible",
        "gh.repo.id": repository.id,
        "gh.enterprise.id": enterprise.id,
        "error.message": e.message,
        "error.class": e.class.name
      )
    rescue StandardError => e
      GitHub.logger.error(
        "Error fetching custom agents",
        "gh.repo.id": repository.id,
        "gh.enterprise.id": enterprise.id,
        "error.message": e.message,
        "error.class": e.class.name,
      )
      deliver_error!(500, message: "An error occurred while fetching custom agents")
    end

    custom_agents
  end

  def set_pagination_headers(paginated_collection)
    return unless paginated_collection.respond_to?(:total_pages)
    return unless paginated_collection.total_pages > 1

    current_page = paginated_collection.current_page
    total_pages = paginated_collection.total_pages
    per_page = paginated_collection.per_page

    # Build pagination links
    @links.add_current({ page: total_pages, per_page: per_page }, rel: "last") if current_page != total_pages
    @links.add_current({ page: current_page + 1, per_page: per_page }, rel: "next") if current_page < total_pages
    if current_page > 1
      @links.add_current({ page: 1, per_page: per_page }, rel: "first")
      @links.add_current({ page: current_page - 1, per_page: per_page }, rel: "prev")
    end
  end
end
