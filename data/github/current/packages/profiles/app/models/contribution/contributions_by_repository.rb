# typed: true
# frozen_string_literal: true

# Public: Collects many contributions a user has made within a repository.
class Contribution::ContributionsByRepository
  STATEFUL_CONTRIBUTION_TYPES = [
    Contribution::CreatedIssue,
    Contribution::CreatedPullRequest,
  ].freeze

  # Public: The repository in which these contributions were made.
  attr_reader :repository

  # Public: Describes the kind of contributions, as a class.
  attr_reader :contribution_type

  # Public: The range of time from which these contributions were pulled.
  attr_reader :time_range

  # Public: The user who made the contributions.
  attr_reader :user

  def initialize(repository:, contributions:, contribution_type:, time_range:, user:)
    @repository = repository
    @contributions = contributions
    @contribution_type = contribution_type
    @user = user
    @time_range = time_range
  end

  # Public: A list of contributions to GitHub made by a user.
  #
  # order_by - Hash describing how to sort the contributions; valid keys:
  #   :field - valid values include "occurred_at", and also "commit_count" when the contributions
  #            are CreatedCommits
  #   :direction - valid values include "ASC" or "DESC"
  #
  # Returns a sorted Array.
  def contributions(order_by: {})
    field = order_by[:field] || "occurred_at"
    direction = order_by[:direction] || "DESC"

    sorted_contributions = if field == "occurred_at"
      @contributions.sort_by(&:occurred_at)
    elsif field == "commit_count"
      unless contribution_type == Contribution::CreatedCommit
        raise "Don't know how to order non-commit contributions by '#{field}'"
      end
      @contributions.sort_by(&:commit_count)
    else
      raise "Don't know how to order contributions by '#{field}'"
    end
    sorted_contributions = sorted_contributions.reverse if direction == "DESC"
    sorted_contributions
  end

  # Public: Break up the contributions by the state they're in. Applicable for issue and
  # pull request contributions.
  #
  # Returns an Array of Contribution::ContributionsByState.
  def contributions_by_state
    return {} unless STATEFUL_CONTRIBUTION_TYPES.include?(contribution_type)

    result = contributions.group_by { |contribution| contribution.state_class.to_s }
    result.map do |state, state_contributions|
      Contribution::ContributionsByState.new(repository: repository, state: state,
                                             contributions: state_contributions,
                                             contribution_type: contribution_type)
    end
  end

  def platform_type_name
    if contribution_type == ::Contribution::CreatedIssue
      "IssueContributionsByRepository"
    elsif contribution_type == ::Contribution::CreatedPullRequest
      "PullRequestContributionsByRepository"
    elsif contribution_type == ::Contribution::CreatedPullRequestReview
      "PullRequestReviewContributionsByRepository"
    elsif contribution_type == ::Contribution::CreatedCommit
      "CommitContributionsByRepository"
    else
      raise Platform::Errors::Internal,
        "Unexpected contribution_type: #{contribution_type.class}"
    end
  end

  def total_count
    @contributions.sum(&:contributions_count)
  end
end
