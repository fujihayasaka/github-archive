# typed: true
# frozen_string_literal: true

class Orgs::CopilotSettings::ChatSettingsController < Orgs::CopilotSettings::BaseController
  extend T::Sig
  include JsonDependency
  include VerifiedFetchDependency

  include ReactHelper
  include ApplicationHelper
  include CopilotAuthHelper
  include CopilotForDocsHelper
  include BlackbirdIndexHelper

  before_action :dotcom_required
  before_action :require_feature_flag
  before_action :org_admins_only
  # See: https://github.com/github/copilot-core-productivity/issues/1219
  before_action :require_can_change_copilot_enterprise_settings

  before_action :try_parse_json_params, only: [:check_name, :create, :update, :destroy]

  @react_bundle_name = "copilot-chat-settings"

  depends_on_clusters ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    only: [:index, :list, :new, :show, :edit]

  allow_verified_fetch only: [:check_name, :create, :destroy, :update]

  sig { void }
  def index
    render_react_app(
      title: "GitHub Copilot Chat settings",
      payload: {
        newKnowledgeBasePath: settings_org_copilot_chat_settings_new_path(current_organization),
        currentOrganizationLogin: current_organization.display_login,
        apiUrl: GitHub.copilot_api_url,
        ssoOrganizations: sso_organizations,
      },
      page_data: { selected_link: :settings_org_copilot_chat_settings },
      layout: "layouts/settings/copilot_org_react",
      ssr: false
    )
  end

  # rubocop:todo GitHub/UseRestfulActions
  sig { void }
  def list
    response = current_user_copilot_api.list_org_knowledge_bases(org_id: current_organization.id)
    knowledge_bases = response[:kbs]
    knowledge_bases = knowledge_bases.map do |knowledge_base|
      # Filter out repos the user doesn't have access to
      kb = secure_and_decorate_docset(knowledge_base.with_indifferent_access)
      # Ensure we only pass the things along that we mean to pass along to the client
      kb.slice(:id, :name, :description, :ownerID, :ownerType, :scopingQuery, :repos, :sourceRepos)
    end
    render json: {
      knowledgeBases: knowledge_bases,
    }
  end

  sig { void }
  def new
    render_react_app(
      title: "Add GitHub Copilot Chat knowledge base",
      payload: {
        docsetOwner: {
          id: current_organization.id,
          isOrganization: true,
          displayLogin: current_organization.display_login,
        },
        apiUrl: GitHub.copilot_api_url,
        ssoOrganizations: sso_organizations,
      },
      page_data: { selected_link: :settings_org_copilot_chat_settings },
      layout: "layouts/settings/copilot_org_react",
      ssr: false
    )
  end

  sig { void }
  def create
    kb = kb_create_payload

    if knowledge_base_valid?(kb)
      result = current_user_copilot_api.create_knowledge_base(kb)

      kb[:repos].each do |nwo|
        repo = Repository.nwo(nwo)
        if repo.nil?
          render json: { message: "Invalid knowledge base" }, status: :bad_request
          return
        end
        trigger_embeddings_indexing(T.must(current_user), repo, index_docs: true)
      end

      Copilot::Instrumenter.instrument_knowledge_base_created(T.must(current_user), get_owner, kb)
      render json: result, status: :created
    else
      render json: { message: "Invalid knowledge base" }, status: :bad_request
    end

    # If the request has the "exceeded maximum of 25 kbs for owner" message, we should return a 400 status code
    # with that message so the user can see it in the UI.
    rescue CopilotAPI::RequestError => e
      message = e.message
      max_kbs = message.match(/exceeded maximum of (\d+) kbs for owner/)
      if max_kbs
        # consider this a very lightweight version of https://jsonapi.org/format/#error-objects
        render json: {
          errors: [
            {
              title: "Knowledge base limit reached",
              detail: "Limit of #{max_kbs[1]} knowledge bases per owner reached, delete one of your existing knowledge bases to create a new one."
            }
          ]
        }, status: :bad_request
      else
        raise e
      end
  end

  sig { void }
  def show
    kb = current_user_copilot_api.get_knowledge_base(knowledge_base_id: params[:id])[:kb]
    return render_404 unless kb

    kb = secure_and_decorate_docset(kb)

    if !kb[:sourceRepos].nil?
      repo_data = kb[:sourceRepos]&.map { |repo| get_source_repo_data(repo.with_indifferent_access) }&.compact || []
    else
      # TODO: remove this conditional statement once we fully move to sourceRepos
      repo_data = kb[:repos]&.map { |nwo| get_repo_data(nwo) }&.compact || []
    end

    owner = kb[:ownerID] == current_organization.id
    return render_404 unless owner

    render json: {
      docset: kb,
      repoData: repo_data,
      docsetOwner: {
        id: current_organization.id,
        isOrganization: true,
        displayLogin: current_organization.display_login,
      }
    }
  end

  sig { void }
  def edit
    render_react_app(
      title: "Edit GitHub Copilot Chat knowledge base",
      page_data: { selected_link: :settings_org_copilot_chat_settings },
      payload: {
        apiUrl: GitHub.copilot_api_url,
        ssoOrganizations: sso_organizations,
        currentOrganizationLogin: current_organization.display_login,
        knowledgeBaseId: params[:id],
      },
      layout: "layouts/settings/copilot_org_react",
      ssr: false
    )
  end

  sig { void }
  def update
    kb = kb_update_payload
    if knowledge_base_valid?(kb)
      result = current_user_copilot_api.update_knowledge_base(params[:id], kb)

      kb[:repos].each do |nwo|
        repo = Repository.nwo(nwo)
        if repo.nil?
          render json: { message: "Invalid knowledge base" }, status: :bad_request
          return
        end
        trigger_embeddings_indexing(T.must(current_user), repo, index_docs: true)
      end

      Copilot::Instrumenter.instrument_knowledge_base_updated(T.must(current_user), get_owner, kb)
      render json: result, status: :no_content
    else
      render json: { message: "Invalid knowledge base" }, status: :bad_request
    end
  rescue CopilotAPI::NotFoundError
    render_404
  end

  sig { void }
  def destroy
    kb = kb_delete_payload

    current_user_copilot_api.delete_knowledge_base(knowledge_base_id: kb[:id])
    Copilot::Instrumenter.instrument_knowledge_base_deleted(T.must(current_user), get_owner, kb)
    head 204
  rescue CopilotAPI::NotFoundError
    render_404
  end

  # rubocop:todo GitHub/UseRestfulActions
  sig { void }
  def check_name
    response = current_user_copilot_api.list_org_knowledge_bases(org_id: current_organization.id)
    all_accessible_kbs = T.cast(response[:kbs] || [], T::Array[ActiveSupport::HashWithIndifferentAccess])
    # There is a conflicting docset if there is a docset with the same owner and the same name.
    # For now, it suffices to check if there is a docset within the organization, because only orgs can own knowledge bases.
    # This becomes more complicated if users can own docsets and/or once we filter docsets access based on repo access (i.e. the
    # user must have access to at least one repo in the docset), because in that case you *could*
    # have an org admin creating a docset that does not have access to a potentially-conflicting
    # docset. So this may eventually need to be revisited, but not yet!
    conflicting_kbs = all_accessible_kbs.select do |kb|
      kb[:ownerID] == params[:ownerID].to_i &&
      kb[:ownerType] == params[:ownerType] &&
      kb[:name].upcase == params[:name].upcase
    end

    render json: { available: conflicting_kbs.empty? }
  end

  sig { returns ::Organization }
  def get_owner
    T.must(Organization.find_by(id: params[:ownerId]))
  end

  private

  sig { returns KbUpdatePayload }
  def kb_update_payload
    {
      name: params[:name],
      description: params[:description],
      scoping_query: scoping_query,
      source_repos: params[:sourceRepos],
      owner_id: params[:ownerId],
      repos: params[:repos],
      visibility: params[:visibility],
    }
  end

  sig { returns KbCreationPayload }
  def kb_create_payload
    {
      name: params[:name],
      description: params[:description],
      scoping_query: scoping_query,
      source_repos: params[:sourceRepos],
      owner_id: params[:ownerId],
      owner_type: params[:ownerType],
      repos: params[:repos],
      visibility: params[:visibility],
    }
  end

  sig { returns KbDeletionPayload }
  def kb_delete_payload
    {
      name: params[:name],
      owner_id: params[:ownerId],
      id: params[:id],
    }
  end

  sig { params(kb: T.any(KbCreationPayload, KbUpdatePayload)).returns(T::Boolean) }
  def knowledge_base_valid?(kb)
    return false unless kb[:name].present? && kb[:name].length <= 100 && kb[:name].match?(/\A[a-z0-9\- .'']+\Z/i)
    return false unless kb[:description].blank? || kb[:description].length <= 1000
    return false unless kb[:repos]&.filter_map(&:presence)&.present? && kb[:repos].length <= 100
    true
  end

  sig { void }
  def require_feature_flag
    render_404 unless feature_enabled_globally_or_for_user?(feature_name: :copilot_dotcom_chat)
  end

  sig { void }
  def require_can_change_copilot_enterprise_settings
    render_404 unless copilot_organization.can_use_copilot_enterprise_features?
  end

  sig { returns Copilot::User::CopilotApi }
  def current_user_copilot_api
    token = T.must(current_user).feature_enabled?(:"copilot-kb-migration") ? nil : GitHub.decode_and_decrypt_capi_token(request&.headers[CopilotAPI::TOKEN_HEADER])

    T.must(current_user).copilot_api(
      integration_id: CopilotAPI::COPILOT_CHAT_INTEGRATION_ID,
      session: user_session,
      real_ip: request&.remote_ip,
      token:
    )
  end

  def scoping_query
    return params[:scopingQuery] unless Flipper.enabled?(:copilot_knowledge_base_scoping_query_builder)

    source_repos = params[:sourceRepos]
    if source_repos.blank?
      GitHub.logger.info(
        "Knowledge base request missing sourceRepos param",
         "gh.copilot.knowledge_base.scoping_query" => params[:scopingQuery]
      )

      return params[:scopingQuery]
    end

    KnowledgeBase::ScopingQuery.from_source_repositories(source_repos:)
  end

  KbCreationPayload = T.type_alias do
    {
      name: T.nilable(String),
      description: T.nilable(String),
      scoping_query: T.nilable(String),
      source_repos: T.nilable(T::Array[SourceRepoPayload]),
      owner_id: T.nilable(String),
      owner_type: T.nilable(String),
      repos: T.nilable(T::Array[String]),
      visibility: T.nilable(String),
    }
  end

  KbUpdatePayload = T.type_alias do
    {
      name: T.nilable(String),
      description: T.nilable(String),
      scoping_query: T.nilable(String),
      source_repos: T.nilable(T::Array[SourceRepoPayload]),
      owner_id: T.nilable(String),
      repos: T.nilable(T::Array[String]),
      visibility: T.nilable(String),
    }
  end

  KbDeletionPayload = T.type_alias do
    {
      name: T.nilable(String),
      owner_id: T.nilable(String),
      id: T.nilable(String),
    }
  end

  SourceRepoPayload = T.type_alias do
    {
        id: Integer,
        owner_id: Integer,
        paths: T::Array[String]
    }
  end
end
