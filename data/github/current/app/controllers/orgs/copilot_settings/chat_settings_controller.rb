# typed: true
# frozen_string_literal: true

class Orgs::CopilotSettings::ChatSettingsController < Orgs::CopilotSettings::BaseController
  include JsonDependency
  include VerifiedFetchDependency

  include ApplicationHelper
  include CopilotAuthHelper
  include BlackbirdIndexHelper

  before_action :dotcom_required
  before_action :require_feature_flag
  before_action :org_admins_only
  # See: https://github.com/github/copilot-core-productivity/issues/1219
  before_action :require_can_change_copilot_enterprise_settings

  before_action :try_parse_json_params, only: [:check_name, :create, :update, :destroy]

  self.react_bundle_name = "copilot-chat-settings"

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
        apiUrl: copilot_api_url,
        ssoOrganizations: sso_organizations,
      },
      page_data: { selected_link: :settings_org_copilot_chat_settings },
      layout: "layouts/settings/copilot_org_react",
      disable_ssr: true
    )
  end

  # rubocop:todo GitHub/UseRestfulActions
  sig { void }
  def list
    response = current_user_copilot_api.list_org_knowledge_bases(org_id: current_organization.id)

    knowledge_bases = response[:kbs]
    knowledge_bases = knowledge_bases.map do |knowledge_base|
      # Filter out repos the user doesn't have access to
      kb = KnowledgeBases::Public.secure_and_decorate_docset(
        current_user:,
        cap_filter:,
        docset: knowledge_base.with_indifferent_access
      )
      # Ensure we only pass the things along that we mean to pass along to the client
      kb.slice(:id, :name, :description, :ownerID, :ownerType, :repos, :sourceRepos)
    end

    render json: {
      knowledgeBases: knowledge_bases,
    }

    rescue CopilotAPI::RequestError => e
      GitHub.dogstats.increment("copilot.knowledge_base.chat_settings.list.request_error")
      GitHub.logger.error("copilot.knowledge_base.chat_settings.list.request_error", {
        "error": e,
        "gh.copilot.knowledge_base.org_id": current_organization.id,
      })

      render json: { message: "Failed to list knowledge bases" }, status: :bad_request

    rescue CopilotAPI::NetworkError => e
      GitHub.dogstats.increment("copilot.knowledge_base.chat_settings.list.network_error")
      GitHub.logger.error("copilot.knowledge_base.chat_settings.list.network_error", {
        "error": e,
        "gh.copilot.knowledge_base.org_id": current_organization.id,
      })

      render json: { message: "Failed to list knowledge bases" }, status: :internal_server_error
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
        apiUrl: copilot_api_url,
        ssoOrganizations: sso_organizations,
      },
      page_data: { selected_link: :settings_org_copilot_chat_settings },
      layout: "layouts/settings/copilot_org_react",
      disable_ssr: true
    )
  end

  sig { void }
  def create
    kb = kb_create_payload

    if knowledge_base_valid?(kb)
      result = current_user_copilot_api.create_knowledge_base(kb)

      GitHub.dogstats.increment("copilot.knowledge_base.chat_settings.kb_created")
      GitHub.logger.info("copilot.knowledge_base.chat_settings.kb_created", {
        "gh.copilot.knowledge_base.id": result,
      })

      if feature_enabled_globally_or_for_user?(feature_name: :copilot_knowledge_base_less_reindexing)
        return if trigger_indexing_for_repos("create", kb[:repos], result).nil?
      else
        kb[:repos].each do |nwo|
          repo = Repository.nwo(nwo)
          if repo.nil?
            render json: { message: "Invalid knowledge base" }, status: :bad_request

            GitHub.dogstats.increment("copilot.knowledge_base.chat_settings.create.invalid_repo")
            GitHub.logger.info("copilot.knowledge_base.chat_settings.create.invalid_repo", {
              "gh.copilot.knowledge_base.id": result,
              "gh.copilot.knowledge_base.repo": nwo,
            })

            return
          end
          status = trigger_embeddings_indexing(T.must(current_user), repo, index_docs: true)

          KnowledgeBases::Public.log_indexing_status("create", result, repo.id, repo.name_with_display_owner, status)
        end
      end

      Copilot::Instrumenter.instrument_knowledge_base_created(T.must(current_user), get_owner, kb)
      render json: result, status: :created
    else
      GitHub.dogstats.increment("copilot.knowledge_base.chat_settings.create.error.invalid_kb")
      GitHub.logger.info("copilot.knowledge_base.chat_settings.create.error.invalid_kb")

      render json: { message: "Invalid knowledge base" }, status: :bad_request
    end

    # If the request has the "exceeded maximum of 25 kbs for owner" message, we should return a 400 status code
    # with that message so the user can see it in the UI.
    rescue CopilotAPI::RequestError => e
      message = e.message
      max_kbs = message.match(/exceeded maximum of (\d+) kbs for owner/)
      if max_kbs
        GitHub.dogstats.increment("copilot.knowledge_base.chat_settings.create.error.max_kbs")
        GitHub.logger.info("copilot.knowledge_base.chat_settings.create.error.max_kbs", {
          "error": e,
        })

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
        GitHub.dogstats.increment("copilot.knowledge_base.chat_settings.create.request_error")
        GitHub.logger.error("copilot.knowledge_base.chat_settings.create.request_error", {
          "error": e,
        })

        render json: { message: "Failed to create knowledge base" }, status: :bad_request
      end
  end

  sig { void }
  def show
    kb = current_user_copilot_api.get_knowledge_base(knowledge_base_id: params[:id])[:kb]

    if !kb
      GitHub.dogstats.increment("copilot.knowledge_base.chat_settings.show.error.kb_not_found")
      GitHub.logger.error("copilot.knowledge_base.chat_settings.show.error.kb_not_found", {
        "gh.copilot.knowledge_base.id": params[:id],
      })
    end

    return render_404 unless kb

    kb = KnowledgeBases::Public.secure_and_decorate_docset(current_user:, cap_filter:, docset: kb)

    repo_data = kb[:sourceRepos]&.map { |repo| KnowledgeBases::Public.get_source_repo_data(repo.with_indifferent_access) }&.compact || []

    owner = kb[:ownerID] == current_organization.id

    if !owner
      GitHub.dogstats.increment("copilot.knowledge_base.chat_settings.show.error.invalid_owner")
      GitHub.logger.error("copilot.knowledge_base.chat_settings.show.error.invalid_owner", {
        "gh.copilot.knowledge_base.id": params[:id],
      })
    end

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

    rescue CopilotAPI::RequestError => e
      GitHub.dogstats.increment("copilot.knowledge_base.chat_settings.show.request_error")
      GitHub.logger.error("copilot.knowledge_base.chat_settings.show.request_error", {
        "error": e,
        "gh.copilot.knowledge_base.id": params[:id],
      })

      render_404

    rescue CopilotAPI::NetworkError => e
      GitHub.dogstats.increment("copilot.knowledge_base.chat_settings.show.network_error")
      GitHub.logger.error("copilot.knowledge_base.chat_settings.show.network_error", {
        "error": e,
        "gh.copilot.knowledge_base.id": params[:id],
      })

      render json: { message: "Failed to get knowledge base" }, status: :internal_server_error
  end

  sig { void }
  def edit
    render_react_app(
      title: "Edit GitHub Copilot Chat knowledge base",
      page_data: { selected_link: :settings_org_copilot_chat_settings },
      payload: {
        apiUrl: copilot_api_url,
        ssoOrganizations: sso_organizations,
        currentOrganizationLogin: current_organization.display_login,
        knowledgeBaseId: params[:id],
      },
      layout: "layouts/settings/copilot_org_react",
      disable_ssr: true
    )
  end

  sig { void }
  def update
    kb = kb_update_payload

    if knowledge_base_valid?(kb)
      result = current_user_copilot_api.update_knowledge_base(params[:id], kb)

      if feature_enabled_globally_or_for_user?(feature_name: :copilot_knowledge_base_less_reindexing)
        return if trigger_indexing_for_repos("update", kb[:repos], result).nil?
      else
        kb[:repos].each do |nwo|
          repo = Repository.nwo(nwo)
          if repo.nil?
            GitHub.dogstats.increment("copilot.knowledge_base.chat_settings.update.invalid_repo")
            GitHub.logger.info("copilot.knowledge_base.chat_settings.update.invalid_repo", {
              "gh.copilot.knowledge_base.id": params[:id],
              "gh.copilot.knowledge_base.repo": nwo,
            })

            render json: { message: "Invalid knowledge base" }, status: :bad_request
            return
          end

          status = trigger_embeddings_indexing(T.must(current_user), repo, index_docs: true)

          KnowledgeBases::Public.log_indexing_status("update", result, repo.id, repo.name_with_display_owner, status)
        end
      end

      Copilot::Instrumenter.instrument_knowledge_base_updated(T.must(current_user), get_owner, kb)
      render json: result, status: :no_content
    else
      GitHub.dogstats.increment("copilot.knowledge_base.chat_settings.update.error.invalid_kb")
      GitHub.logger.info("copilot.knowledge_base.chat_settings.update.error.invalid_kb", {
        "gh.copilot.knowledge_base.id": params[:id],
      })

      render json: { message: "Invalid knowledge base" }, status: :bad_request
    end

  rescue CopilotAPI::NotFoundError
    GitHub.dogstats.increment("copilot.knowledge_base.chat_settings.update.error.kb_not_found")
    GitHub.logger.error("copilot.knowledge_base.chat_settings.update.error.kb_not_found", {
      "gh.copilot.knowledge_base.id": params[:id],
    })

    render_404

  rescue CopilotAPI::RequestError => e
    GitHub.dogstats.increment("copilot.knowledge_base.chat_settings.update.request_error")
    GitHub.logger.error("copilot.knowledge_base.chat_settings.update.request_error", {
      "error": e,
      "gh.copilot.knowledge_base.id": params[:id],
    })

    render json: { message: "Failed to update knowledge base" }, status: :bad_request
  end

  sig { void }
  def destroy
    kb = kb_delete_payload

    current_user_copilot_api.delete_knowledge_base(knowledge_base_id: kb[:id])

    GitHub.dogstats.increment("copilot.knowledge_base.chat_settings.kb_deleted")
    GitHub.logger.info("copilot.knowledge_base.chat_settings.kb_deleted", {
      "gh.copilot.knowledge_base.id": kb[:id],
    })

    Copilot::Instrumenter.instrument_knowledge_base_deleted(T.must(current_user), get_owner, kb)
    head 204

  rescue CopilotAPI::NotFoundError
    GitHub.dogstats.increment("copilot.knowledge_base.chat_settings.destroy.error.kb_not_found")
    GitHub.logger.error("copilot.knowledge_base.chat_settings.destroy.error.kb_not_found", {
      "gh.copilot.knowledge_base.id": T.must(kb)[:id],
    })

    render_404

  rescue CopilotAPI::RequestError => e
    GitHub.dogstats.increment("copilot.knowledge_base.chat_settings.destroy.request_error")
    GitHub.logger.error("copilot.knowledge_base.chat_settings.destroy.request_error", {
      "error": e,
      "gh.copilot.knowledge_base.id": T.must(kb)[:id],
    })

    render json: { message: "Failed to delete knowledge base" }, status: :bad_request
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

  sig { returns(String) }
  memoize def copilot_api_url
    Copilot::SKUIsolation.for_user(current_user).api.endpoint
  end

  sig { returns KbUpdatePayload }
  def kb_update_payload
    {
      name: params[:name],
      description: params[:description],
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

  sig { params(action: String, nwos: T::Array[String], knowledge_base_result: T.untyped).returns(T.nilable(T::Array[T.any(Symbol, String)])) }
  def trigger_indexing_for_repos(action, nwos, knowledge_base_result)
    statuses = []
    # There's no good way to avoid an n+1 here.
    repos = nwos.map do |nwo|
      repo = Repository.nwo(nwo)
      if repo.nil?
        render json: { message: "Invalid knowledge base" }, status: :bad_request

        GitHub.dogstats.increment("copilot.knowledge_base.chat_settings.#{action}.invalid_repo")
        GitHub.logger.info("copilot.knowledge_base.chat_settings.#{action}.invalid_repo", {
          "gh.copilot.knowledge_base.id": knowledge_base_result,
          "gh.copilot.knowledge_base.repo": nwo,
        })

        return nil
      end
      repo
    end

    indexed_repo_ids = CopilotIndexedRepositories.where(repository: repos).pluck(:repository_id)

    # only index repos that aren't already indexed
    repos.reject { |repo| indexed_repo_ids.include?(repo.id) }.each do |repo|
      status = trigger_embeddings_indexing(T.must(current_user), repo, index_docs: true)
      KnowledgeBases::Public.log_indexing_status(action, knowledge_base_result, repo.id, repo.name_with_display_owner, status)
      statuses << status
    end

    # Return value is ignored in the caller for now
    statuses
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
    T.must(current_user).copilot_api(
      integration_id: CopilotAPI::COPILOT_CHAT_INTEGRATION_ID,
      session: user_session,
      real_ip: request&.remote_ip,
    )
  end

  KbCreationPayload = T.type_alias do
    {
      name: T.nilable(String),
      description: T.nilable(String),
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
