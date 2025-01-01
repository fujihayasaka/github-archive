# typed: true
# frozen_string_literal: true

class Reminders::RepositorySuggestionsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :organization, :query, :teams

  MAX_LIMIT = 100
  INITIAL_SUGGESTION_LIMIT = 20

  def suggestions(limit: MAX_LIMIT)
    return initial_suggestions unless query.present?

    # enforce a maximum cap
    limit = MAX_LIMIT if limit > MAX_LIMIT

    @suggestions ||= begin
      scope = suggestable_repositories

      exact_match = scope.where("repositories.name = :query", query: query).first

      scope = scope.where("repositories.name like :query", query: "%#{ActiveRecord::Base.sanitize_sql_like(query)}%")
      scope = scope.select([:id, :name, :owner_id, :parent_id, :public, :description, :source_id])
      scope = scope.order("repositories.name").limit(limit)

      scope.to_a.prepend(exact_match).uniq.compact
    end
  end

  def initial_suggestions
    @initial_suggestions ||= begin
      scope = suggestable_repositories
      scope.recently_updated.limit(INITIAL_SUGGESTION_LIMIT)
    end
  end

  def suggestable_repositories
    scope = if teams.present?
      Team.repositories_scope(teams: teams, affiliation: :all)
    else
      organization.repositories
    end

    # Scope to what the integration has access to
    integration = Apps::Privileged.integration(:slack)
    if integration
      integration_installation = integration.installations_on(organization).first
      if integration_installation && !integration_installation.installed_on_all_repositories?
        scope = scope.where(id: integration_installation.repository_ids)
      end
    end

    scope = scope.active.not_archived_scope
    scope = scope.public_scope unless organization.plan_supports?(:reminders, visibility: :private, fallback_to_free: false)
    scope
  end
end
