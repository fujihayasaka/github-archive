# frozen_string_literal: true

require "github_helpers"

class CloseOutdatedPullRequests
  attr_reader :pull_request

  def initialize(pull_request:)
    @pull_request = pull_request
  end

  def run
    return if previous_dependabot_prs.none?

    previous_dependabot_prs.each do |pr|
      # This pull request must be a superset of the dependencies in the previous PR
      next unless superset_of_dependencies?(pr)

      pr_detail = open_prs.find { |detail| detail.number == pr.github_number }

      # The outdated PR wasn't fetched from GitHub because it is already closed.
      next if pr_detail.nil?

      # The outdated PR was somehow fetched from GitHub despite being closed.
      next if pr_detail.state == "closed"

      # The outdated PR has been updated by someone other than dependabot.
      next if edited_and_shouldnt_be_overwritten?(pr, pr_detail)

      supersede_pull_request(pr, pull_request)

      # Update the assignees on the new PR to match those on the
      # old one. (NOTE: It would be even better to not have to supersede at all)
      update_pr_assignees(pr_detail, pull_request)
    end
  end

  private

  def dependency_set
    @dependency_set ||= Set.new(pull_request.updated_dependencies.map(&:name))
  end

  def directory_set
    @directory_set ||= Set.new(pull_request.updated_dependencies.map(&:directory))
  end

  def previous_dependabot_prs
    return @previous_dependabot_prs if defined?(@previous_dependabot_prs)

    @previous_dependabot_prs = PullRequest.where(repo: pull_request.repo).
                               where("#{PullRequest.table_name}.created_at < ?", pull_request.created_at).
                               open.
                               joins(:update_config).
                               where(update_config: {
                                       package_manager: package_managers,
                                       target_branch: pull_request.update_config.target_branch,
                                     }).
                               joins(:update_job).
                               where(update_job: {
                                       security_updates_only: pull_request.update_job.security_updates_only?,
                                     }).
                               includes(:updated_dependencies)
  end

  def package_managers
    if pull_request.multi_ecosystem_config_id?
      pull_request.multi_ecosystem_config.update_configs.pluck(:package_manager)
    else
      pull_request.update_config.package_manager
    end
  end

  # close the PR if the updated dependencies contain all the dependencies that the existing one has
  def superset_of_dependencies?(candidate) # rubocop:disable Metrics/AbcSize, Metrics/PerceivedComplexity
    if candidate.updated_dependencies.first.directory.nil?
      candidate_dependency_set = Set.new(candidate.updated_dependencies.map(&:name))
      candidate_dependency_set.subset?(dependency_set)
    else
      candidate_directory_set = Set.new(candidate.updated_dependencies.map(&:directory))
      return false unless candidate_directory_set.subset?(directory_set)

      directory_set.all? do |directory|
        dependency_set = Set.new(
          pull_request.updated_dependencies.select { |dep| dep.directory == directory }.map(&:name)
        )
        candidate_dependency_set = Set.new(
          candidate.updated_dependencies.select { |dep| dep.directory == directory }.map(&:name)
        )
        candidate_dependency_set.subset?(dependency_set)
      end
    end
  end

  def open_prs
    # TODO: Handle lists longer than 100
    @open_prs ||=
      installation_github_client.pull_requests(
        pull_request.repo.github_id,
        state: "open",
        per_page: 100,
      ).select do |pr|
        previous_dependabot_prs.map(&:github_number).include?(pr.number)
      end
  end

  def edited_and_shouldnt_be_overwritten?(pull_request, pr_detail)
    return false unless PullRequestCommits.new(pull_request: pull_request).
                        pr_has_been_edited?(head_sha: pr_detail.head.sha)

    # The pull request has been edited but requested a recreate
    !pull_request.
      pull_request_transitions.
      where(to_state: "updating").
      order(:sort_key).last&.
      metadata&.fetch("overwrite_edits", nil)
  end

  def supersede_pull_request(pull_request, new_pull_request)
    comment_on_superseded_pull_request(pull_request, new_pull_request)

    begin
      ClosePullRequest.new(pull_request: pull_request).run
    rescue ClosePullRequest::GitHubCloseBug
      # Sometimes commenting on a PR immediately before attempting to close it
      # causes a validation error. In that case, enqueue a job to close it later
      ClosePullRequestJob.
        set(wait: 1.second).
        perform_later(
          pull_request: pull_request,
          comment_on_pr: false,
        )
    end
  end

  def comment_on_superseded_pull_request(pull_request, new_pull_request)
    CreateComment.new(
      pull_request: pull_request,
      comment_body: "Superseded by ##{new_pull_request.github_number}.",
    ).run
  end

  def update_pr_assignees(old_pull_request_details, new_pull_request)
    assignees = old_pull_request_details.assignees.map(&:login)
    # Temporary hack to work around a GitHub bug
    assignees.reject! { |nm| nm.end_with?("[bot]") }
    return unless assignees.any?

    default_assignees = new_pull_request.update_config.default_assignees || []
    return if assignees == default_assignees

    installation_github_client.add_assignees(
      new_pull_request.repo.github_id,
      new_pull_request.github_number,
      assignees,
    )
  end

  def installation_github_client
    @installation_github_client ||=
      GitHubHelpers::ClientWithRetries.
      new(account: pull_request.repo.account)
  end
end
