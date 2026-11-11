# typed: strict
# frozen_string_literal: true

class Copilot::Chat::RepositoriesSearchController < Copilot::Chat::AbstractChatController
  depends_on_clusters(
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Profiles,
    ApplicationRecord::Repositories,
    only: [:index],
  )

  # GET /github-copilot/chat/repositories_search
  # Params:
  #   q: search query (optional, returns top repos if empty)
  #   limit: max number of results (optional, default 10)
  #   includeForks: include forked repositories (optional, default true)
  #   currentRepoId: ID of current repository to prioritize (optional)
  #   owner: owner login to filter repositories by (optional, used for org-owned spaces)
  sig { void }
  def index
    repositories = repository_search.search(
      query: params[:q].to_s.strip,
      limit: params[:limit]&.to_i,
      include_forks: params[:includeForks] != "false",
      current_repo_id: params[:currentRepoId]&.to_i,
      owner: params[:owner].presence,
    )

    render json: {
      repositories: repositories.map { |repo| repository_to_topic_item(repo) }
    }
  end

  private

  sig { returns(Copilot::Chat::RepositorySearch) }
  memoize def repository_search
    Copilot::Chat::RepositorySearch.new(
      user: current_user,
      user_session: user_session,
      remote_ip: remote_ip,
      cap_filter: cap_filter,
    )
  end

  sig { params(repo: Repository).returns(T::Hash[Symbol, T.untyped]) }
  def repository_to_topic_item(repo)
    owner = T.must(repo.owner)
    {
      id: repo.id,
      databaseId: repo.id,
      name: repo.name,
      nameWithOwner: repo.name_with_display_owner,
      ownerLogin: owner.display_login,
      ownerAvatar: helpers.avatar_url_for(owner, 40),
      ownerType: owner.is_a?(Organization) ? "Organization" : "User",
      isInOrganization: owner.is_a?(Organization),
      isPrivate: repo.private?,
      visibility: repo.visibility,
    }
  end

  # CAP is not bypassed here as AbstractChatController requires a logged in user.
  sig { returns(T.any(User, Symbol)) }
  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    current_user
  end

  # CAP is not bypassed here as AbstractChatController requires a logged in user.
  sig { returns(T.any(User, Symbol)) }
  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end
end
