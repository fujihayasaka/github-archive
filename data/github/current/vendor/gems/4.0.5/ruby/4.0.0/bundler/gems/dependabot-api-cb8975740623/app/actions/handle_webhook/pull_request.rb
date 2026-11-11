# frozen_string_literal: true

module HandleWebhook
  class PullRequest
    attr_reader :webhook_body

    def initialize(webhook_body:)
      @webhook_body = webhook_body
    end

    def run
      case webhook_body[:action]
      when "reopened" then handle_pr_reopened
      when "closed" then handle_pr_closed
      end
    rescue Octokit::Unauthorized
      retrying ||= false
      raise if retrying

      retrying = true
      uncache_installation_client
      retry
    end

    private

    def handle_pr_reopened
      return if dependabot_pr.nil?

      dependabot_pr.event_stream.record_event(Activity::PullRequestEvents::REOPENED,
                                              tags: { "gh.actor.id": webhook_body[:sender][:id] })
      resync_pr_state
      remove_ignore_condition_if_required
      enqueue_pr_update
    end

    def enqueue_pr_update
      return unless dependabot_pr.update_config.automatically_rebase_prs? ||
                    dependabot_pr.merge_requested?

      RebasePullRequestIfNewCommitsJob.perform_later(
        pull_request: dependabot_pr,
      )
    end

    def handle_pr_closed
      return if dependabot_pr.nil?

      event_constant = if webhook_body[:pull_request][:merged]
                         Activity::PullRequestEvents::MERGED
                       else
                         Activity::PullRequestEvents::CLOSED
                       end
      dependabot_pr.event_stream.record_event(event_constant,
                                              tags: { "gh.actor.id": webhook_body[:sender][:id] })
      resync_pr_state
      create_version_skip_comment
      enqueue_branch_deletion
    end

    def resync_pr_state
      ResyncPrStateJob.perform_later(pull_request: dependabot_pr)
    end

    def remove_ignore_condition_if_required
      dependabot_pr.updated_dependencies.each do |dep|
        remove_ignore_condition_if_required_for(dep)
      end
    end

    def remove_ignore_condition_if_required_for(dependency)
      ignore_conditions =
        dependabot_pr.update_job.update_config.ignore_conditions.
        reject(&:from_config_file?).
        select { |ic| ic.dependency_name == dependency.name }.
        select { |ic| ic.includes?(dependency.version) }

      # TODO: We should probably use a state machine for ignore conditions
      ignore_conditions.each(&:destroy!)
    end

    def create_version_skip_comment
      return if webhook_body[:pull_request][:merged]
      return if webhook_body[:pull_request][:commits]&.zero?
      return if webhook_body[:sender][:login] == "#{integration_name}[bot]"

      CreateVersionSkipComment.new(pull_request: dependabot_pr).run
    rescue Octokit::AbuseDetected, Octokit::TooManyRequests
      CreateVersionSkipCommentJob.
        set(wait: 10.seconds).
        perform_later(pull_request: dependabot_pr)
    end

    def enqueue_branch_deletion
      return if webhook_body[:sender][:login] == "#{integration_name}[bot]"

      DeletePullRequestBranchJob.
        set(wait: 5.seconds).
        perform_later(pull_request: dependabot_pr)
    end

    def dependabot_pr
      return @dependabot_pr if defined?(@dependabot_pr)

      @dependabot_pr = ::PullRequest.joins(:repo).find_by(
        repos: { github_id: webhook_body[:repository][:id] },
        github_number: webhook_body[:pull_request][:number],
      )
    end

    def uncache_installation_client
      GitHubHelpers.delete_cached_access_token_for(
        account: dependabot_pr.repo.account,
      )
      @installation_github_client = nil
    end

    def installation_github_client
      @installation_github_client ||=
        GitHubHelpers::ClientWithRetries.
        new(account: dependabot_pr.repo.account)
    end

    def integration_name
      Prius.get(:github_integration_name)
    end
  end
end
