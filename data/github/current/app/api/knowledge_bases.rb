# typed: true
# frozen_string_literal: true

class Api::KnowledgeBases < Api::App
  include ReceiveSchemaWithOpenApi
  # List repositories for the authenticated user.
  get "/user/knowledge-bases", operation_id: "knowledge-bases/list-for-authenticated-user" do
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

  get "/organizations/:organization_id/knowledge-bases/:knowledge_base_id", operation_id: "knowledge-bases/get" do
    org = find_org!

    require_enabled_copilot_enterprise_org!(org)

    control_access :get_knowledge_base,
    resource: org,
    challenge: true,
    allow_integrations: true,
    allow_user_via_granular_actor: true

    knowledge_base_id = params[:knowledge_base_id]

    resp = current_user_copilot_api.get_knowledge_base(knowledge_base_id:)
    result = KnowledgeBases::Public.from_cosmos_response(current_user:, cap_filter:, cosmos_data: resp[:kb])

    unauthorized_sso_org_ids = result.unauthorized_sso_org_ids
    knowledge_base = result.knowledge_bases.first

    set_sso_partial_results_header(unauthorized_sso_org_ids) if unauthorized_sso_org_ids.any?

    if unauthorized_sso_org_ids.any? && knowledge_base.nil?
      deliver_error 403
    else
      deliver :knowledge_base_hash, knowledge_base
    end

  rescue CopilotAPI::NotFoundError
    deliver_error 404
  end

  get "/organizations/:organization_id/knowledge-bases", operation_id: "knowledge-bases/list-for-organization" do
    org = find_org!

    require_enabled_copilot_enterprise_org!(org)

    control_access :get_knowledge_base,
      resource: org,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    resp = current_user_copilot_api.list_org_knowledge_bases(org_id: org.id)
    result = KnowledgeBases::Public.from_cosmos_response(current_user:, cap_filter:, cosmos_data: resp[:kbs])

    set_sso_partial_results_header(result.unauthorized_sso_org_ids) if result.unauthorized_sso_org_ids.any?

    deliver_error! 403 if result.unauthorized_sso_org_ids.include?(org.id)

    deliver :knowledge_base_hash, result.knowledge_bases

  rescue CopilotAPI::NotFoundError
    deliver_error 404
  end

  sig { returns Copilot::User::CopilotApi }
  def current_user_copilot_api
    T.must(current_user).copilot_api(
      integration_id: CopilotAPI::COPILOT_CHAT_INTEGRATION_ID,
      session: web_session,
      real_ip: remote_ip,
      token: Copilot::DecryptedToken.from(request_credentials.token),
    )
  end

  sig { params(org: Organization).void }
  def require_enabled_copilot_enterprise_org!(org)
    deliver_error! 404 unless Copilot::Organization.new(org).can_use_copilot_enterprise_features? &&
      Flipper[:copilot_org_knowledge_bases_api].enabled?(org)
  end
end
