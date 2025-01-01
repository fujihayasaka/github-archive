# typed: true
# frozen_string_literal: true

class Issues::References::LinkableItemsComponent < ApplicationComponent
  attr_reader :manual_xref_pull_requests,
    :manual_xref_branches,
    :xref_pull_requests,
    :pull_requests,
    :branches,
    :manual_reference_ids_at_limit,
    :manual_xref_pull_requests_count_all_repos,
    :max_manual_reference_count

  # manual_xref_pull_requests: [PullRequest]
  #   Manually linked pull requests from issue sidebar
  # manual_xref_branches: Git::Ref[]
  #   Manually linked branches from issue sidebar or <create-branch> dialog
  # xref_pull_requests: [PullRequest]
  #   Other pull requests that are linked to the issue, e.g. by "closes" keyword in a pull request
  # pull_requests: [PullRequest]
  #   All pull requests that could be linked to the issue
  # branches: Git::Ref[]
  #   All branches that could be linked to the issue
  # manual_reference_ids_at_limit: [Integer]
  #   Pull request IDs that are manually linked to the issue
  # manual_xref_pull_requests_count_all_repos: Integer
  #   The number of manual xref pull requests across all repositories
  # max_manual_reference_count: Integer
  #   The maximum number of pull requests that can be linked to the issue
  def initialize(
    manual_xref_pull_requests: [],
    manual_xref_branches: [],
    xref_pull_requests: [],
    pull_requests: [],
    branches: [],
    manual_reference_ids_at_limit: [],
    manual_xref_pull_requests_count_all_repos: 0,
    max_manual_reference_count: 0
  )
    @manual_xref_pull_requests = manual_xref_pull_requests
    @manual_xref_branches = manual_xref_branches
    @xref_pull_requests = xref_pull_requests
    @pull_requests = pull_requests
    @branches = branches
    @manual_reference_ids_at_limit = manual_reference_ids_at_limit
    @manual_xref_pull_requests_count_all_repos = manual_xref_pull_requests_count_all_repos
    @max_manual_reference_count = max_manual_reference_count
  end

  def no_results?
    manual_xref_pull_requests.empty? &&
    manual_xref_branches.empty? &&
    xref_pull_requests.empty? &&
    pull_requests.empty? &&
    branches.empty?
  end

  def at_limit?
    remaining <= 0
  end

  def remaining
    max_manual_reference_count - manual_xref_pull_requests_count_all_repos
  end

end
