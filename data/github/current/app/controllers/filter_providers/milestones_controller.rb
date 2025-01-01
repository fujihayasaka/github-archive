# typed: true
# frozen_string_literal: true

class FilterProviders::MilestonesController < FilterProvidersController
  include FilterProviders::RepositoriesDependency

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:index, :show]

  # Both the index and show actions rely on the `repository_ids_for_context` method
  # from the RepositoriesDependency module, which makes use of the CAP filter under the hood.
  # Therefore, we can skip the CAP filter checks on these actions and reduce some of the overhead on the request.
  skip_before_action :perform_conditional_access_checks, only: [:index, :show] # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  MILESTONE_LIMIT = 100

  def index
    respond_payload({
      milestones: fetch_milestones.map { |m| format_response(m) }
    })
  end

  def show
    if milestone_from_query.present?
      respond_payload(format_response(milestone_from_query))
    else
      head :unprocessable_entity
    end
  end

  private

  def fetch_milestones
    return [] unless repository_ids_for_context.any?

    scope = Milestone.includes(:repository).where(repository_id: repository_ids_for_context)
    scope = scope.where("title LIKE ?", like_query_value) if has_search_query?
    scope.order(:title).limit(MILESTONE_LIMIT)
  end

  def format_response(milestone)
    {
      title: milestone.title,
      description: milestone.repository.name_with_display_owner,
      value: "#{milestone.repository.name_with_display_owner}/#{milestone.number}"
    }
  end

  memoize def milestone_from_query
    return nil unless repository_ids_for_context.any?
    Milestone.includes(:repository).find_by(title: query_value, repository_id: repository_ids_for_context)
  end
end
