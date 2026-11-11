# typed: true
# frozen_string_literal: true

class Orgs::TeamRepositories::SuggestionsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :team, :query

  def suggestions
    @suggestions ||= begin
      organization_repositories = Repository.active.where(organization_id: team.organization_id)
      organization_repositories = organization_repositories.search(query) unless query.blank?

      filter_repository_ids = organization_repositories.ids - team.repository_ids

      repository_ids = current_user.associated_repository_ids(min_action: :admin, repository_ids: filter_repository_ids)
      workspace_repository_ids = RepositoryAdvisory.where(workspace_repository_id: repository_ids).pluck(:workspace_repository_id)
      repository_ids = repository_ids - workspace_repository_ids

      Repository.active.where(id: repository_ids)
    end
  end

  def suggestions?
    suggestions.any?
  end

  def user_query?
    !email_query?
  end

  def email_query?
    false # you can't add repos by email
  end
end
