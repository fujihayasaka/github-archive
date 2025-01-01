# typed: true
# frozen_string_literal: true

class FilterProviders::RepositoriesController < FilterProvidersController
  include Suggestions::RepositoriesDependency
  include FilterProviders::RepositoriesDependency

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Iam

  def index
    respond_payload({ repositories: repositories_payload(query: query_value, limit: maximum_result_limit) })
  end

  def show
    if repo_from_query
      respond_payload(format_response(repo_from_query))
    else
      head :unprocessable_entity
    end
  end

  private

  memoize def repo_from_query
    return nil unless query_value.present? && query_value.include?("/")
    repo = Repository.with_name_with_owner(query_value)
    return repo if repo && repo.readable_by?(current_user)
    nil
  end

  def resource_for_conditional_access
    return self unless action_name == "show"
    return :no_resource_for_conditional_access if repo_from_query.nil? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    repo_from_query
  end

  def target_for_conditional_access
    repo_from_query&.owner || current_user || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
