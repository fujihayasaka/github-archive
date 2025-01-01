# typed: true
# frozen_string_literal: true

class FilterSuggestions::MilestonesController < ApplicationController
  include DashboardHelper
  include FilterSuggestions::FilterSuggestionsDependency

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories,
    ApplicationRecord::IamAbilities

  layout false
  before_action :login_required

  REPO_LIMIT = 25
  MILESTONE_LIMIT = 100

  def index
    milestones = fetch_milestones.map do |milestone|
      {
        title: milestone.title,
        description: milestone.repository.name_with_display_owner,
        value: "#{milestone.repository.name_with_display_owner}/#{milestone.number}"
      }
    end

    respond_payload({ milestones: milestones })
  end

  private

  def fetch_milestones
    if query_in_shorthand_form?
      milestones = milestones_for_shorthand_query
      return milestones if milestones.present?
    end

    if static_repo_context
      milestones_for_repos([static_repo_context.id], filter_value)
    else
      milestones_for_repos(top_repo_ids, filter_value)
    end
  end

  # Returns milestones for queries containing a shorthand form like "owner/repo/milestone number"
  def milestones_for_shorthand_query
    owner, name, number = filter_value&.downcase.split("/")
    return [] unless owner.present? && name.present?

    repo = Repository.find_by(owner_login: owner, name: name)
    return [] unless repo

    if number
      number = number.to_i
      return [] if number.zero?

      # If the user provided the number of a specific milestone, we can look that up directly
      [Milestone.find_by(repository_id: repo.id, number: number)].compact
    else
      milestones_for_repos([repo.id])
    end
  end

  def milestones_for_repos(repo_ids, title_query = "")
    scope = Milestone.includes(:repository).where(repository_id: repo_ids)
    scope = scope.where("title LIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(title_query)}%") if title_query.present?
    scope.order(:title).limit(MILESTONE_LIMIT)
  end

  memoize def top_repo_ids
    fetch_top_repositories(page: 1, per_page: REPO_LIMIT, initial_per_page: REPO_LIMIT).pluck(:id)
  end

  memoize def static_repo_context
    return nil unless repositories_from_query.any?
    repositories_from_query.first
  end

  memoize def filter_value
    params[:filter_value] || ""
  end

  def query_in_shorthand_form?
    filter_value.split("/").size >= 2
  end

  def resource_for_conditional_access
    :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
  end

  def target_for_conditional_access
    current_user || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  # anonymous requests 401 so only enforce for non anonymous
  def tenant_verification_enforceable
    current_user ? :yes : :no
  end
end
