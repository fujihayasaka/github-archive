# frozen_string_literal: true

class CreatePullRequestOnDependabot < ApplicationJob
  queue_as :default
  default_retries_for_idempotent_jobs

  # github_pull_request is a hashified MonolithTwirp::Dependabot::PullRequests::V1::PullRequest
  def perform(pending_pr:, github_pull_request: nil)
    @pending_pr = pending_pr
    @update_config = pending_pr.update_config
    @update_job = pending_pr.update_job
    @github_pull_request = github_pull_request

    update_job.increment_metric("create_pull_request_on_dependabot.attempt")

    pull_request = create_pull_request
    run_post_create_hooks(pull_request:)
    update_job.increment_metric("create_pull_request_on_dependabot.success")
  rescue StandardError => e
    update_job.increment_metric("create_pull_request_on_dependabot.error", tags: { error: e.class.name })
    Dependabot::Logger.log_exception(
      e,
      {
        msg: "Error creating pull request on Dependabot",
        **pending_pr.telemetry_attributes,
      }
    )

    raise e
  end

  private

  attr_reader :pending_pr, :update_config, :update_job, :github_pull_request

  def existing_pull_request
    @existing_pull_request ||=
      PullRequest.find_by(
        repo_id: update_config.repo.id,
        github_number: pr_number
      )
  end

  def create_pull_request
    return existing_pull_request if existing_pull_request.present?

    PullRequest.create!(pull_request_attributes).tap do |pull_request|
      pending_pr.updated_dependencies.each do |dependency|
        create_updated_dependency(dependency:, pull_request:)
      rescue ActiveRecord::RecordInvalid => e
        pull_request.update_job.update_job_errors.create!(
          error_type: "pull_request_creation_failure",
          error_details: {
            message: "Dependabot wasn't able to track a dependency",
          }
        )

        log_updated_dependency_creation_failure(dependency, e)
      end
    end
  rescue ActiveRecord::RecordInvalid => e
    handle_pull_request_creation_failure(e)
  end

  def pull_request_attributes
    {
      github_number: pr_number,
      update_job_id: update_job.id,
      update_config_id: update_config.id,
      repo_id: update_config.repo.id,
      head_commit_sha: head_sha,
      dependabot_commit_sha: head_sha,
      base_commit_sha: base_sha,
      multiple_dependencies: pending_pr.updated_dependencies.count > 1,
      grouped_update: pending_pr.dependency_group.present?,
      dependency_group: pending_pr.dependency_group,
      affected_directories: pending_pr.updated_dependency_files.map(&:directory).uniq.sort,
    }
  end

  def create_updated_dependency(dependency:, pull_request:)
    record = UpdatedDependency.from_dependabot_dependency(dependency)
    record.pull_request = pull_request
    record.save!
  end

  def run_post_create_hooks(pull_request:)
    return if pull_request.blank?

    pending_pr.transition_to(:created)

    enqueue_pull_request_ci_status_check(pull_request)
    record_end_to_end_timing(update_job)

    CloseOutdatedPullRequests.new(pull_request:).run
  end

  def enqueue_pull_request_ci_status_check(created_pr)
    UpdatePullRequestCiStatusJob.perform_later(
      pull_request: created_pr,
      refs_to_check: [
        created_pr.base_commit_sha,
        created_pr.head_commit_sha,
      ],
    )
  end

  def record_end_to_end_timing(update_job)
    return unless update_job.triggered_at

    duration = Time.now.utc - update_job.triggered_at
    update_job.timing_metric(
      "dependency_update.success",
      duration,
      tags: {
        language: update_job.language,
        grouped_update: pending_pr.grouped_update?,
        runner_type: update_job.runner_type,
        v2: true,
      }
    )
  end

  def log_updated_dependency_creation_failure(dependency, error)
    Dependabot::Logger.error(
      msg: "Dependabot failed to create an UpdatedDependency",
      "exception.message": error.record.errors.full_messages.join("\n"),
      "code.namespace": self.class.name,
      "gh.repo.id": update_config.repo.github_id,
      "gh.dependabot_api.pull_request.github_number": pr_number,
      "gh.dependabot_api.pull_request.dependency_name": dependency.name
    )
  end

  def handle_pull_request_creation_failure(error)
    # notify users of our PR creation failure
    update_job.update_job_errors.create(
      error_type: "internal_pull_request_creation_failure",
      error_details: {
        github_number: pr_number,
      }
    )

    Dependabot::Logger.error(
      msg: "Dependabot failed to create a PullRequest",
      "exception.message": error.record.errors.full_messages.join("\n"),
      "code.namespace": self.class.name,
      "gh.repo.id": update_config.repo.github_id,
      "gh.dependabot_api.pull_request.github_number": pr_number,
    )

    MetricsClient.increment("create_pull_request_on_dependabot.failure")
  end

  def pr_number
    github_pull_request[:github_number]
  end

  def head_sha
    github_pull_request[:head_sha]
  end

  def base_sha
    github_pull_request[:base_sha]
  end
end
