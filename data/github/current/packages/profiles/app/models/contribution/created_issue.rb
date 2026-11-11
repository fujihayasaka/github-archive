# typed: true
# frozen_string_literal: true

class Contribution::CreatedIssue < Contribution
  LIGHTWEIGHT_ATTRIBUTE_SELECT_LIST = [
    :contributed_at_offset,
    :contributed_at_timestamp,
    :created_at,
    :id,
    :issue_comments_count,
    :number,
    :pull_request_id,
    :repository_id,
    :state,
    :title,
    :user_hidden,
    :user_id,
  ].freeze
  LIMIT_FOR_FIRST_ISSUE_QUERY = 20

  def async_repository
    subject.async_repository
  end

  # Public: Returns state of the pull request as a Symbol. (e.g. :merged)
  def state_class
    issue.state
  end

  # Public: The total number of comments on the issue.
  # Returns an Integer.
  def comments_count
    issue.issue_comments_count
  end

  def issue
    subject
  end

  def associated_subject
    issue.repository
  end

  def organization_id
    associated_subject.try(:organization_id)
  end

  # Public: Returns the issue's contribution time as a Time.
  def occurred_at
    issue.contribution_time
  end

  def eql?(other_contribution)
    other_contribution.respond_to?(:issue) && issue == other_contribution.issue
  end

  def hash
    issue.hash
  end

  def repository_id
    issue.repository_id
  end

  def platform_type_name
    "CreatedIssueContribution"
  end

  # Public: whether this contribution was created before the given other contribution.
  #
  # CreatedIssue contributions are ordered by their created_at time, then by their id.
  #
  # Returns a Boolean.
  def created_before?(other)
    raise ArgumentError, "contribution type mismatch" unless other.is_a?(self.class)
    created_at == other.created_at ? id < other.id : created_at < other.created_at
  end

  delegate :state, :repository, :contribution_time, :title, :number, :id, :created_at,
           to: :issue

  def self.subjects_for(
    user,
    date_range:,
    organization_id: nil,
    excluded_organization_ids: [],
    lightweight: false
  )
    Contribution.measure("created_issue_subjects_for", tags: ["lightweight:#{lightweight}", "using_contribution_fetchers:false"]) do
      scope = user
        .issues
        .includes(:repository)
        .where(pull_request_id: nil, created_at: buffered_time_range(date_range))
        .limit(Contribution::DEFAULT_COUNT_LIMIT)

      if lightweight
        scope = scope.reselect(LIGHTWEIGHT_ATTRIBUTE_SELECT_LIST)
      end

      if organization_id
        scope = scope.select do |issue| # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          issue.repository.organization_id == organization_id
        end
      end

      if excluded_organization_ids.any?
        scope.select do |issue| # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          next false unless issue.repository
          !issue.repository.organization_id.in?(excluded_organization_ids)
        end
      else
        scope
      end
    end
  end

  def self.first_subject_for(user, excluded_organization_ids: [])
    # Getting the first issue for a non-orphaned repository can be a
    # slow query, so only run it if this faster query indicates there
    # will be data. See https://github.com/github/github/issues/69815.
    return unless user.issues.without_pull_requests.exists? # domain-isolation-query-violation:ignore:packages/issues (SELECT)

    Contribution.measure("created_issue_first_subject_for", tags: ["using_contribution_fetchers:false"]) do
      scope = user
        .issues
        .includes(:repository)
        .reselect(LIGHTWEIGHT_ATTRIBUTE_SELECT_LIST)
        .where(pull_request_id: nil)
        .order(created_at: :asc)
        .limit(LIMIT_FOR_FIRST_ISSUE_QUERY)

      scope.find do |issue| # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        issue.repository&.active? &&
          !issue.repository.organization_id.in?(excluded_organization_ids)
      end
    end
  end

  def self.needs_filtering_by_occurred_at?
    true
  end
end
