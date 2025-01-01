# typed: true
# frozen_string_literal: true

class Stafftools::KnowledgeBasesController < StafftoolsController
  layout "layouts/stafftools/user/content"

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
    ApplicationRecord::Ballast,
    only: [:index, :show]

  before_action :dotcom_required
  before_action :eligible_for_copilot_enterprise_required

  def index
    render "stafftools/knowledge_bases/index", locals: {
      copilot_organization:,
      knowledge_bases:,
    }
  end

  def show
    render "stafftools/knowledge_bases/show", locals: {
      copilot_organization:,
      knowledge_base:,
      repositories:,
    }
  end

  def update_repo_description # rubocop:todo GitHub/UseRestfulActions
    embedding = embed_description(params[:description]) if params[:description].present?
    copilot_api.update_knowledge_base_repo_description(params[:id], params[:repo_id], params[:description], embedding)
    redirect_to stafftools_user_knowledge_base_path(this_user, id: params[:id])
  end

  private

  def repositories
    return [] if knowledge_base.nil? || knowledge_base[:sourceRepos].nil?

    ids = knowledge_base[:sourceRepos].map { |repo| repo[:id] }
    source_repos_map = knowledge_base[:sourceRepos].to_h { |repo| [repo[:id], repo] }

    repos = Repositories::Public.load_repositories(ids.uniq)
    repos.map do |repo|
      {
        id: repo.id,
        name: repo.name_with_display_owner,
        indexing_status: repo_index_status(repo),
        auto_generated_description: source_repos_map[repo.id][:description],
      }
    end
  end

  sig { returns(Copilot::Organization) }
  def copilot_organization
    Copilot::Organization.new(this_user)
  end

  def knowledge_bases
    copilot_api.list_org_knowledge_bases(org_id: this_user.id)[:kbs]
  rescue  Exception => e
    []
  end

  def knowledge_base
    copilot_api.get_knowledge_base(knowledge_base_id: params[:id])[:kb]
  rescue  Exception => e
    nil
  end

  sig { returns(Copilot::User::CopilotApi) }
  def copilot_api
    current_user.copilot_api(
      integration_id: CopilotAPI::COPILOT_KNOWLEDGE_BASE_INTEGRATION_ID,
    )
  end

  sig { params(repo: Repository).returns(Symbol) }
  def repo_index_status(repo)
    cir = CopilotIndexedRepositories.find_by(repository: repo.id)
    if cir.nil?
      :not_indexed
    else
      cir.semantic_code_search_ok? ? :indexed : :indexing
    end
  end

  sig { void }
  def eligible_for_copilot_enterprise_required
    render_404 unless copilot_organization.eligible_for_copilot_enterprise?
  end

  sig { params(description: String).returns(T.untyped) }
  def embed_description(description)
    begin
      result = copilot_api.create_embedding(model: "text-embedding-3-small", input: description)
      result["data"][0]["embedding"]
    rescue CopilotAPI::Error => e
      Rails.logger.error("Failed to embed repo summary: #{e}.")
    end
  end
end
