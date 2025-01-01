# typed: false
# frozen_string_literal: true

# Public: Collects issue or pull request contributions based on the state the issue or PR is in.
class Contribution::ContributionsByState
  # Public: The repository in which these contributions were made.
  attr_reader :repository

  # Public: A String representing the state the contributions are in, e.g., "open".
  attr_reader :state

  # Public: Describes the kind of contributions as a class, e.g., Contribution::CreatedIssue.
  attr_reader :contribution_type

  def initialize(repository:, state:, contributions:, contribution_type:)
    @repository = repository
    @state = state
    @contributions = contributions
    @contribution_type = contribution_type
  end

  # Public: How many contributions are in this state?
  #
  # Returns an integer.
  def total_contributions
    @contributions.size
  end

  def platform_type_name
    if contribution_type == ::Contribution::CreatedIssue
      "IssueContributionsByState"
    elsif contribution_type == ::Contribution::CreatedPullRequest
      "PullRequestContributionsByState"
    else
      raise Platform::Errors::Internal,
        "Unexpected contribution_type: #{object.contribution_type.class}"
    end
  end
end
