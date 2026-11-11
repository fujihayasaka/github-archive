# typed: true
# frozen_string_literal: true

class Contribution::CreatedPullRequest < Contribution
  REPOSITORY_LIMIT = 5000
  LIGHTWEIGHT_ATTRIBUTE_SELECT_LIST = [
    :base_repository_id,
    :base_ref,
    :base_sha,
    :base_user_id,
    :contributed_at_offset,
    :contributed_at_timestamp,
    :created_at,
    :head_repository_id,
    :head_sha,
    :head_user_id,
    :id,
    :merged_at,
    :repository_id,
    :user_hidden,
    :work_in_progress,
    :review_comments_with_body_count,
    :reviews_with_body_count
  ].freeze

  def self.fetcher_class
    Contribution::Fetcher::CreatedPullRequest
  end

  def async_repository
    subject.async_repository
  end

  def async_issue
    pull_request.async_issue
  end

  def pull_request
    subject
  end

  # Public: Returns the pull request's contribution time as a Time.
  def occurred_at
    pull_request.contribution_time
  end

  def eql?(other_contribution)
    other_contribution.respond_to?(:pull_request) && pull_request == other_contribution.pull_request
  end

  def hash
    pull_request.hash
  end

  def repository
    return @repository if defined?(@repository)
    @repository = pull_request.async_repository.sync
  end

  def organization_id
    repository.try(:organization_id)
  end

  def associated_subject
    repository
  end

  def repository_id
    pull_request.repository_id
  end

  # Public: Returns state of the pull request as a Symbol. (e.g. :merged)
  def state_class
    pull_request.state
  end

  delegate :number, :id, :created_at, to: :pull_request

  def platform_type_name
    "CreatedPullRequestContribution"
  end

  def self.subjects_for(
  user,
  date_range:,
  organization_id: nil,
  excluded_organization_ids: [],
  lightweight: false
  )
    Contribution.measure(
      "created_pull_request_subjects_for",
      tags: ["lightweight:#{lightweight}", "using_contribution_fetchers:false"],
      ) do
        scope = user.pull_requests.where(created_at: buffered_time_range(date_range))
        scope = scope.limit(Contribution::DEFAULT_COUNT_LIMIT)

        if excluded_organization_ids.any? && organization_id
          scope = filter_by_organization_and_exclude_organizations(scope, excluded_organization_ids, organization_id)
        elsif !excluded_organization_ids.any? && organization_id
          scope = filter_by_organization(scope, organization_id)
        elsif excluded_organization_ids.any? && !organization_id
          scope = filter_by_excluded_organizations(scope, excluded_organization_ids, organization_id)
        end

        if lightweight
          scope = scope.reselect(LIGHTWEIGHT_ATTRIBUTE_SELECT_LIST)
        end
        scope.preload(:issue, repository: :owner).to_a # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      end
  end

  def self.filter_by_organization_and_exclude_organizations(scope, excluded_organization_ids, organization_id)
    repo_ids = scope.pluck(:repository_id)
    filtered_repos = Repository.where(id: repo_ids, organization_id: organization_id).active
    filtered_repo_ids = filtered_repos.where.not(organization_id: excluded_organization_ids)
      .or(filtered_repos.where(organization_id: nil))
      .pluck(:id)
    scope = scope.where(repository_id: filtered_repo_ids)
  end

  def self.filter_by_organization(scope, organization_id)
    pr_repo_ids = scope.select(:repository_id).distinct.pluck(:repository_id)
    filtered_repo_ids = Repositories::Public.filter_repo_ids_to_org(
      organization_id: organization_id,
      repo_ids: pr_repo_ids).pluck(:id)
    scope = scope.where(repository_id: filtered_repo_ids)
  end

  def self.filter_by_excluded_organizations(scope, excluded_organization_ids, organization_id)
    repo_ids = scope.pluck(:repository_id)
    filtered_repos = Repository.where(id: repo_ids).active
    filtered_repo_ids = filtered_repos.where.not(organization_id: excluded_organization_ids)
      .or(filtered_repos.where(organization_id: nil))
      .pluck(:id)
    scope = scope.where(repository_id: filtered_repo_ids)
  end

  def self.first_subject_for(user, excluded_organization_ids: [])
    Contribution.measure(
      "created_pull_request_first_subject_for",
      tags: ["using_contribution_fetchers:false"]
    ) do
      repo_id_to_pr_id_map = PullRequest.where(user:).group(:repository_id).limit(REPOSITORY_LIMIT).minimum(:id)

      filtered_repo_ids = Repository.where(id: repo_id_to_pr_id_map.keys).active
      if excluded_organization_ids.any?
        filtered_repo_ids = filtered_repo_ids.where.not(organization_id: excluded_organization_ids).or(filtered_repo_ids.where(organization_id: nil))
      end
      filtered_repo_ids = filtered_repo_ids.pluck(:id)

      minimum_pr_id = repo_id_to_pr_id_map.values_at(*filtered_repo_ids).min

      minimum_pr_id.nil? ? nil : user.pull_requests.find_by(id: minimum_pr_id)
    end
  end

  def self.needs_filtering_by_occurred_at?
    true
  end

  def self.most_popular_from(contributions)
    pull_request_ids = contributions.map(&:id)
    most_popular_pull_request_id = Issue.
      where(pull_request_id: pull_request_ids, issue_comments_count: 1..).
      order(issue_comments_count: :desc).
      limit(1).
      pluck(:pull_request_id, :issue_comments_count). # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      first&.
      first

    contributions.find { |pull_request| pull_request.id == most_popular_pull_request_id }
  end
end
