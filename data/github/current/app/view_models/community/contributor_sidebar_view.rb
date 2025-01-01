# typed: true
# frozen_string_literal: true

class Community::ContributorSidebarView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :current_repository, :issue
  include UrlHelper
  include RepositoryContributorHelper

  def repository_security_policy_path(*args)
    urls.repository_security_policy_path(*args)
  end

  def show_first_time_contributor_sidebar?
    return false unless has_community_guidelines_files?
    contribution_type = issue.pull_request? ? PullRequest : Issue
    show_first_time_contributor_sidebar_for?(contribution_type: contribution_type)
  end

  def show_prior_contributor_sidebar?
    return false unless logged_in?
    return false if current_repository.private? && !GitHub.enterprise?
    if issue.pull_request?
      return false unless !!contributing_file || !!code_of_conduct_file
    else
      return false unless has_community_guidelines_files?
    end
    return false unless has_user_contributed?

    last_update = get_last_update

    # Sometimes the GitRPC request can fail on large repositories, so `last_update`
    # returns `nil`. See https://github.com/github/ce-community-and-safety/issues/1092.
    return false unless last_update.present?

    (last_update.author != current_user) && (last_update.created_at > last_contribution_date)
  end

  def show_helpful_resources?
    has_community_guidelines_files? ||
      # When the repo lacks its own guidelines files in dotcom, we can still link
      # to the GitHub Community Guidelines
      !GitHub.enterprise?
  end

  def contributing_last_updated_date
    last_commit_date(current_repository.preferred_contributing)
  end

  def code_of_conduct_last_updated_date
    last_commit_date(current_repository.preferred_code_of_conduct)
  end

  def security_policy_file_last_updated_date
    if current_repository.security_policy.exists?
      last_commit_date(current_repository.preferred_security_policy)
    end
  end

  def support_last_updated_date
    last_commit_date(current_repository.preferred_support)
  end

  # Public: returns the DateTime of the most recent Issue, Pull Request, or Commit
  # contribution by the current user in the current repository.
  #
  # Returns a DateTime or nil if there are no contributions.
  def last_contribution_date
    user_id = current_user.id
    repository_id = current_repository.id
    contributions = [
      CommitContributions.domain.last_contribution_date(user: current_user, repository: current_repository)&.beginning_of_day,
      Issue.for_repository(repository_id).for_user(user_id).last&.created_at, # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      PullRequest.for_repository(repository_id).for_user(user_id).last&.created_at,
    ]
    contributions.compact.max
  end

  def ga_string(file_name, contributor_type)
    is_helpful_resources = !show_first_time_contributor_sidebar? &&
      !show_prior_contributor_sidebar?
    "New #{issue.pull_request? ? 'pr' : 'issue'}, click #{file_name} link in sidebar#{" (helpful resources)" if is_helpful_resources} (#{contributor_type} contributor), repo:#{current_repository.name_with_display_owner}"
  end

  def contribution_type
    issue.pull_request? ? "a pull request" : "an issue"
  end

  private

  def has_user_contributed?
    contrib_types = [Issue, PullRequest, CommitContribution]
    contrib_types.any? do |contrib_type|
      current_repository.contributor?(current_user, type: contrib_type)
    end
  end

  def get_last_update
    updates = [
      last_commit(current_repository.preferred_contributing),
      last_commit(current_repository.preferred_code_of_conduct),
    ]
    unless issue.pull_request?
      updates << last_commit(current_repository.preferred_security_policy)
      updates << last_commit(current_repository.preferred_support)
    end

    updates.compact.max_by(&:created_at)
  end

  def last_commit(file)
    file_path = file.try(:path)
    return unless file_path
    file.repository.commits.last_touched(file.repository.default_branch, file_path)
  end

  def last_commit_date(file)
    last_commit(file).try(:created_at)
  end
end
