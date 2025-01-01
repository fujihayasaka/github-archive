# typed: strict
# frozen_string_literal: true

class Businesses::AdvancedSecurity::SuggestionFlow::RepositoriesController < Businesses::AdvancedSecurity::SuggestionFlow::BaseController
  sig { void }
  def show
    render :show
  end

  sig { void }
  def update
    selected_repos = selected_repos(params[:selected_repo_ids])
    GitHub.kv.set(selected_repos_key, selected_repos.map(&:id).join(",")) # rubocop:todo GitHub/DoNotUseGlobalKv
    head :ok
  end

  private

  sig { params(ids: T::Array[Integer]).returns(T::Array[Repository]) }
  def selected_repos(ids)
    Repository.where(organization_id: selected_org_ids, id: ids).order(:id).limit(1000).to_a
  end
end
