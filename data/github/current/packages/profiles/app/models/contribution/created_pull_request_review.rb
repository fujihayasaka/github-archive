# typed: true
# frozen_string_literal: true

class Contribution::CreatedPullRequestReview < Contribution
  LIGHTWEIGHT_ATTRIBUTE_SELECT_LIST = [
    :id,
    :pull_request_id,
    :state,
    :submitted_at,
    :user_id,
  ].freeze

  def self.subjects_for(
    user,
    date_range:,
    organization_id: nil,
    excluded_organization_ids: [],
    lightweight: false
  )
    Contribution.measure(
      "created_pull_request_review_subjects_for",
      tags: ["lightweight:#{lightweight}", "using_contribution_fetchers:false"],
    ) do
      time_range = date_range_to_time_range(date_range)

      if lightweight
        reviews = user.reviews.submitted.where(submitted_at: time_range, user_hidden: false)
      else
        reviews = user.reviews.visible_in_timeline_for(nil).where(submitted_at: time_range)
      end

      reviews = reviews.for_organization(organization_id) if organization_id
      if excluded_organization_ids.any?
        all_repo_ids = reviews.pluck(:repository_id)
        filtered_repos = Repository.where(id: all_repo_ids)
        filtered_repos = filtered_repos.where(organization_id: nil).or(filtered_repos.where.not(organization_id: excluded_organization_ids))
        filtered_repo_ids = filtered_repos.pluck(:id)

        reviews = reviews.where(repository_id: filtered_repo_ids)
      end

      # Preload PR & repo
      reviews = reviews.preload(pull_request: :repository).limit(Contribution::DEFAULT_COUNT_LIMIT)

      # We only have to join to the pull_requests table to make sure we're
      # omitting reviews that no longer have a pull request. See
      # https://github.com/github/github/issues/64386#issuecomment-258510294
      # But make sure we are not creating an extra (redundant) join on pull_requests
      # See https://github.com/github/github/issues/154801
      reviews = reviews.joins(:pull_request) unless reviews.joins_values.include?(:repository)

      if lightweight
        reviews = reviews.reselect(LIGHTWEIGHT_ATTRIBUTE_SELECT_LIST)
      end

      reviews_by_pr_id = reviews.group_by(&:pull_request_id)
      reviews_by_pr_id.map { |_pull_request_id, pr_reviews| pr_reviews.max_by(&:submitted_at) }
    end
  end

  def pull_request_review
    subject
  end

  def pull_request
    pull_request_review.pull_request
  end

  def repository
    pull_request.repository
  end

  def organization_id
    repository.try(:organization_id)
  end

  def repository_id
    pull_request.repository_id
  end

  def associated_subject
    repository
  end

  def occurred_at
    pull_request_review.submitted_at
  end

  def name_with_owner
    repository.name_with_display_owner
  end

  def title
    pull_request.title
  end

  def platform_type_name
    "CreatedPullRequestReviewContribution"
  end
end
