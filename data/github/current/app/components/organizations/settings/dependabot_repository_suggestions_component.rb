# typed: true
# frozen_string_literal: true

class Organizations::Settings::DependabotRepositorySuggestionsComponent < ApplicationComponent
  DEFAULT_SUGGESTIONS = 15

  def initialize(org:, query:, limit: DEFAULT_SUGGESTIONS)
    @org = org
    @query = query
    @limit = limit
  end

  memoize def repositories
    if @query.blank?
      return []
    end

    scope = selectable_repos

    exact_match = scope.where("repositories.name" => @query).first

    scope = scope.where("repositories.name like :query", query: "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%")
    scope = scope.order(:name).limit(@limit)

    scope.to_a.prepend(exact_match).uniq.compact.first(@limit)
  end

  private

  def selectable_repos
    scope = @org.repositories.private_scope

    # advisory workspace repos can't be accessed by dependabot
    workspace_repo_ids = @org.owned_advisory_workspace_repositories.pluck(:id)
    scope = scope.without_ids(workspace_repo_ids) if workspace_repo_ids.any?

    scope.without_ids(selected_repo_ids).preload(:mirror)
  end

  def selected_repo_ids
    Dependabot::Twirp.repository_access_service_client.get_repository_access(owner_github_id: @org.id)
      .repository_github_ids
  end
end
