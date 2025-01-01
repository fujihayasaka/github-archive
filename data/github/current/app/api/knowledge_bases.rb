# typed: true
# frozen_string_literal: true

class Api::KnowledgeBases < Api::App
  include ReceiveSchemaWithOpenApi
  include BlackbirdIndexHelper

  ORG_KB_LIMIT_MESSAGE = "This org has reached the knowledge base limit, delete one of your existing knowledge bases to create a new one."

  # Get a list of knowledge bases in the specified organization.
  get "/organizations/:organization_id/knowledge-bases", operation_id: "knowledge-bases/list-for-organization" do
    check_kbs_disabled!
    org = find_org!

    require_enabled_copilot_enterprise_org!(org)

    control_access :get_knowledge_base,
      resource: org,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    resp = current_user_copilot_api.list_org_knowledge_bases(org_id: org.id)

    source_repos = resp[:kbs].map { |kb| kb[:sourceRepos] }.flatten
    source_repo_ids = source_repos.map { |source_repo| source_repo[:id] }
    accessible_repos = user_accessible_repos(source_repo_ids)

    result = KnowledgeBases::Public.from_cosmos_response(current_user:, cap_filter:, cosmos_data: resp[:kbs], authorized_org_id: org.id, accessible_repos:)

    # repositories that belong to SAML-protected organizations may be excluded from the response
    unauthorized_sso_org_ids = cap_filter.unauthorized_resource_ids(current_user&.organizations, only: :saml)
    set_sso_partial_results_header(unauthorized_sso_org_ids) if unauthorized_sso_org_ids.any?

    deliver :knowledge_base_hash, result.knowledge_bases

  rescue CopilotAPI::NotFoundError
    deliver_error 404
  end

  # Create a new knowledge base in the specified organization.
  post "/organizations/:organization_id/knowledge-bases", operation_id: "knowledge-bases/create" do
    check_kbs_disabled!
    org = find_org!

    require_enabled_copilot_enterprise_org!(org)

    control_access :administer_knowledge_base,
    resource: org,
    challenge: true,
    allow_integrations: true,
    allow_user_via_granular_actor: true

    data = receive_with_openapi

    repo_ids = data["repositories"].map { |r| r["repository_id"] }.sort

    if repo_ids.uniq.length != repo_ids.length
      deliver_error! 422, message: "Duplicate repository ids in the request"
    end

    accessible_repos = user_accessible_repos(repo_ids).sort
    accessible_repo_ids = accessible_repos.map(&:id).compact.sort

    # If the user doesn't have access to all the input repos, return a 422
    deliver_error! 422 if accessible_repo_ids != repo_ids

    # We need to convert the input repos to the format that CAPI expects
    source_repos = data["repositories"].map do |repo|
      {
        id: repo["repository_id"],
        owner_id: T.must(accessible_repos.find { |r| r.id == repo["repository_id"] }).owner_id,
        paths: repo["file_path_filters"] || []
      }
    end

    # We also need to get the repo nwos for the repos param
    repo_nwos = accessible_repos.map(&:name_with_owner_for_api)

    resp = current_user_copilot_api.create_knowledge_base({
      name: data["name"],
      description: data["description"],
      source_repos:,
      owner_id: org.id,
      owner_type: "organization",
      repos: repo_nwos,
      visibility: "private"
    })

    deliver_error! 500, message: "Failed to create knowledge base" if resp[:id].nil?

    content_sources = data["repositories"].map do |repo|
      KnowledgeBase::ContentSource.new(
        repository_id: repo["repository_id"],
        file_path_filters: repo["file_path_filters"] || []
      )
    end

    knowledge_base = KnowledgeBase.new(
      id: resp[:id],
      name: data["name"],
      description: data["description"],
      owner: org,
      repositories: accessible_repos,
      content_sources:
    )

    # Trigger indexing for the repos in the knowledge base
    accessible_repos.each do |repo|
      status = trigger_embeddings_indexing(T.must(current_user), repo, index_docs: true)

      log_indexing_status("create", knowledge_base.id, repo.id, repo.name_with_owner_for_api, status)
    end

    deliver :knowledge_base_hash, knowledge_base

  rescue CopilotAPI::NotFoundError
    deliver_error 404
  rescue CopilotAPI::RequestError => e
    max_kbs = e.message.match(/exceeded maximum of (\d+) kbs for owner/)
    deliver_error! 422, message: ORG_KB_LIMIT_MESSAGE if max_kbs

    deliver_error 500
  end

  # Get a knowledge base by ID in the specified organization.
  get "/organizations/:organization_id/knowledge-bases/:knowledge_base_id", operation_id: "knowledge-bases/get" do
    check_kbs_disabled!
    org = find_org!

    require_enabled_copilot_enterprise_org!(org)

    control_access :get_knowledge_base,
    resource: org,
    challenge: true,
    allow_integrations: true,
    allow_user_via_granular_actor: true

    knowledge_base_id = params[:knowledge_base_id]
    resp = current_user_copilot_api.get_knowledge_base(knowledge_base_id:)

    deliver_error! 404 if resp.dig(:kb, :ownerID) != org.id

    source_repos = resp[:kb][:sourceRepos]
    source_repo_ids = source_repos&.map { |source_repo| source_repo[:id] }.uniq
    accessible_repos = user_accessible_repos(source_repo_ids)

    deliver_error! 403 if accessible_repos.empty?

    result = KnowledgeBases::Public.from_cosmos_response(current_user:, cap_filter:, cosmos_data: resp[:kb], authorized_org_id: org.id, accessible_repos:)

    # repositories that belong to SAML-protected organizations may be excluded from the response
    unauthorized_sso_org_ids = cap_filter.unauthorized_resource_ids(current_user&.organizations, only: :saml)
    set_sso_partial_results_header(unauthorized_sso_org_ids) if unauthorized_sso_org_ids.any?

    knowledge_base = result.knowledge_bases.first

    deliver :knowledge_base_hash, knowledge_base

  rescue CopilotAPI::NotFoundError
    deliver_error 404
  end

  # Update a knowledge base by ID in the specified organization.
  put "/organizations/:organization_id/knowledge-bases/:knowledge_base_id", operation_id: "knowledge-bases/update" do
    check_kbs_disabled!
    org = find_org!

    require_enabled_copilot_enterprise_org!(org)

    control_access :administer_knowledge_base,
    resource: org,
    challenge: true,
    allow_integrations: true,
    allow_user_via_granular_actor: true

    knowledge_base_id = params[:knowledge_base_id]

    data = receive_with_openapi

    # Get the knowledge base
    resp = current_user_copilot_api.get_knowledge_base(knowledge_base_id:)
    deliver_error! 404 if resp.dig(:kb, :ownerID) != org.id

    # Get repo ids
    repo_ids = data["repositories"].map { |r| r["repository_id"] }.sort

    if repo_ids.uniq.length != repo_ids.length
      deliver_error! 422, message: "Duplicate repository ids in the request"
    end

    accessible_repos = user_accessible_repos(repo_ids).sort
    accessible_repo_ids = accessible_repos.map(&:id).compact.sort

    # If the user doesn't have access to all the input repos, return a 422
    deliver_error! 422 if accessible_repo_ids != repo_ids

    # We need to convert the input repos to the format that CAPI expects
    source_repos = data["repositories"].map do |repo|
      {
        id: repo["repository_id"],
        owner_id: T.must(accessible_repos.find { |r| r.id == repo["repository_id"] }).owner_id,
        paths: repo["file_path_filters"] || []
      }
    end

    # We also need to get the repo nwos for the repos param
    repo_nwos = accessible_repos.map(&:name_with_owner_for_api)

    current_user_copilot_api.update_knowledge_base(knowledge_base_id, {
      name: data["name"],
      description: data["description"],
      source_repos:,
      repos: repo_nwos
    })

    content_sources = data["repositories"].map do |repo|
      KnowledgeBase::ContentSource.new(
        repository_id: repo["repository_id"],
        file_path_filters: repo["file_path_filters"] || []
      )
    end

    updated_knowledge_base = KnowledgeBase.new(
      id: knowledge_base_id,
      name: data["name"],
      description: data["description"],
      owner: org,
      repositories: accessible_repos,
      content_sources: content_sources
    )

    # Trigger indexing for repos in the knowledge base
    accessible_repos.each do |repo|
      status = trigger_embeddings_indexing(T.must(current_user), repo, index_docs: true)

      log_indexing_status("update", knowledge_base_id, repo.id, repo.name_with_owner_for_api, status)
    end

    deliver :knowledge_base_hash, updated_knowledge_base

  rescue CopilotAPI::NotFoundError
    deliver_error 404
  end

  # Delete a knowledge base by ID in the specified organization.
  delete "/organizations/:organization_id/knowledge-bases/:knowledge_base_id", operation_id: "knowledge-bases/delete" do
    check_kbs_disabled!
    org = find_org!

    require_enabled_copilot_enterprise_org!(org)

    control_access :administer_knowledge_base,
    resource: org,
    challenge: true,
    allow_integrations: true,
    allow_user_via_granular_actor: true

    saml_unauthorized_org_ids = cap_filter.unauthorized_resource_ids(org)
    if !saml_unauthorized_org_ids.empty?
      set_sso_partial_results_header(saml_unauthorized_org_ids)
      deliver_error! 403
    end

    knowledge_base_id = params[:knowledge_base_id]
    resp = current_user_copilot_api.get_knowledge_base(knowledge_base_id:)

    deliver_error! 404 if resp.dig(:kb, :ownerID) != org.id

    current_user_copilot_api.delete_knowledge_base(knowledge_base_id:)
    deliver_empty status: 204

  rescue CopilotAPI::NotFoundError
    deliver_error 404
  end

  # List knowledge bases for the authenticated user.
  get "/user/knowledge-bases", operation_id: "knowledge-bases/list-for-authenticated-user" do
    check_kbs_disabled!
    control_access :list_current_user_accessible_knowledge_bases,
      resource: current_user,
      challenge: true,
      allow_integrations: false, # Since we're scoping to the current user, server to server doesn't apply
      allow_user_via_granular_actor: true

    resp = current_user_copilot_api.list_knowledge_bases
    result = KnowledgeBases::Public.from_cosmos_response(current_user:, cap_filter:, cosmos_data: resp[:kbs])

    set_sso_partial_results_header(result.unauthorized_sso_org_ids) if result.unauthorized_sso_org_ids.any?
    deliver :knowledge_base_hash, result.knowledge_bases
  end

  sig { returns(Copilot::User::CopilotApi) }
  def current_user_copilot_api
    # Default to a nil token so we utilize service-to-service authentication (HMAC key)
    T.must(current_user).copilot_api(
      integration_id: CopilotAPI::COPILOT_KNOWLEDGE_BASE_INTEGRATION_ID,
      session: web_session,
      real_ip: remote_ip,
    )
  end

  sig { params(org: Organization).void }
  def require_enabled_copilot_enterprise_org!(org)
    deliver_error! 404 unless Copilot::Organization.new(org).can_use_copilot_enterprise_features?
  end

  sig { params(repo_ids: T::Array[Integer]).returns(T::Array[Repository]) }
  def user_accessible_repos(repo_ids)
    # Filter repos associated with the user
    associated_repository_ids = current_user.associated_repository_ids(
      repository_ids: repo_ids
    )

    # Filter again for fine-grained actors
    associated_repository_ids = ProgrammaticActor::RepositoryFilter.perform(
      actor: current_user,
      repository_ids: associated_repository_ids
    )

    # Get the user accessible repos
    accessible_repositories = Repositories::Public.accessible_repositories(
      repository_ids: repo_ids,
      associated_repository_ids: associated_repository_ids
    )

    cap_filter.authorized_resources(accessible_repositories.to_a)
  end

  # Copied method here from copilot for docs helper due to dependency on ApplicationController
  def log_indexing_status(api_method, kb_id, repo_id, repo_nwo, status)
    GitHub.dogstats.increment("api.knowledge_bases.#{api_method}.embeddings_indexing", tags: ["status:#{status}"])
    GitHub.logger.info("api.knowledge_bases.#{api_method}.embeddings_indexing", {
      "gh.copilot.knowledge_base.id": kb_id,
      "gh.copilot.knowledge_base.repo_id": repo_id,
      "gh.copilot.knowledge_base.repo_nwo": repo_nwo,
      "gh.copilot.knowledge_base.embeddings_indexing_status": status,
    })
  end

  def check_kbs_disabled!
    if FeatureFlag.vexi.enabled?(:kb_sunset, current_user, default: false) && !FeatureFlag.vexi.enabled?(:kb_sunset_override, current_user, default: false)
      deliver_error! 404, message: "Knowledge Bases have been deprecated and are no longer available."
    end
  end
end
