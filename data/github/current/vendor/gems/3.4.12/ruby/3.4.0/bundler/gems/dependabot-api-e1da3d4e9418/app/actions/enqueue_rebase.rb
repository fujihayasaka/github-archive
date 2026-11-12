# frozen_string_literal: true

require "github_helpers"

class EnqueueRebase
  include GitHub::Telemetry::Traces::Traceable

  class InvalidTransitionReset < StandardError; end

  def initialize(pull_request:, github_details:, overwrite_edits: false, manual: false)
    @pull_request = pull_request
    @github_details = github_details
    @overwrite_edits = overwrite_edits
    @manual = manual
  end

  def run
    tracer.in_span("#{self.class.name}#run") do
      # Ignore the request if there's already one in progress
      # TODO: we should log this or surface to the user?
      return if pull_request.currently_updating?

      # If the pull request is "updating" it's probably stuck because the update
      # job didn't call back, this will "unstick" the pull request and allow the
      # rebase to continue
      transition_pull_request_to_up_to_date

      return if rebasing_paused?
      return if update_config_deleted?

      transitioned = pull_request.transition_to(:updating, overwrite_edits: overwrite_edits)

      return unless transitioned

      jobs = pull_request.create_rebase_update_jobs(manual: manual)
      return reset_transition if jobs.blank?

      unless update_pull_request_description
        delete_all_pending_jobs(jobs)
        return reset_transition
      end

      update_transition_with_job_id(jobs.first)

      jobs.each { |job| PrioritizedJobs::StartUpdateJob.perform_later(job) }
    end
  end

  private

  attr_reader :pull_request, :github_details, :overwrite_edits, :manual

  def rebasing_paused?
    # manual actions should bypass any pause
    return false if manual

    pull_request.repo.paused?
  end

  def update_config_deleted?
    pull_request.update_config.in_state?(:deleted)
  end

  def transition_pull_request_to_up_to_date
    Statesman::Machine.retry_conflicts do
      pull_request.transition_to(:up_to_date) if pull_request.in_state?(:updating)
    end
  end

  def update_pull_request_description
    updating_warning = "[//]: # (dependabot-start)\n"\
                       "⚠️  **Dependabot is rebasing this PR** ⚠️ \n\n"\
                       "Rebasing might not happen immediately, so don't worry "\
                       "if this takes some time.\n\n"\
                       "Note: if you make any changes to this PR yourself, "\
                       "they will take precedence over the rebase.\n\n"\
                       "---\n\n"\
                       "[//]: # (dependabot-end)\n\n"

    UpdatePullRequestBody.new(
      pull_request: pull_request,
      updated_body: updating_warning + github_details.body,
    ).run
  end

  def delete_all_pending_jobs(jobs)
    raise InvalidTransitionReset unless jobs.all? { |job| job.in_state?(:pending) }

    jobs.delete_all
  end

  def reset_transition
    pull_request.transition_to(:up_to_date)
  end

  def update_transition_with_job_id(job)
    transition = pull_request.last_transition
    raise "Expected updating PR!" unless transition.to_state == "updating"

    transition.update!(update_job: job)
  end
end
