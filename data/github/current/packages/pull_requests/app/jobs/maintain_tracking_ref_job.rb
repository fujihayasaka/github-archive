# typed: true
# frozen_string_literal: true

class MaintainTrackingRefJob < ApplicationJob
  # Raised in place of ThreepcBusyError when the backoff feature flag is enabled,
  # so that a separate retry_on with polynomially_longer backoff handles the retry.
  # This is temporary so that we can roll this out beginning with Anthropic's mono repo.
  class ThreepcBusyBackoffError < StandardError; end

  MAX_CONCURRENT_JOBS = 3
  RESTRAINT_LOCK_TTL = 10.minutes
  RESTRAINT_LOCK_KEY_PREFIX = "maintain_tracking_ref_job:repo"

  use_replicas ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Spokes,
    ApplicationRecord::RepositoriesPushes

  retry_on_dirty_exit
  queue_as do
    _, _, opts = T.unsafe(self).arguments

    if opts && opts[:importing]
      :maintain_tracking_ref_importing
    else
      :maintain_tracking_ref
    end
  end

  retry_on GitHub::DGit::ThreepcError
  retry_on GitHub::DGit::ThreepcBusyError
  retry_on GitHub::DGit::ThreepcFailedToLock
  retry_on ThreepcBusyBackoffError, wait: :polynomially_longer, attempts: 5

  retry_on GitHub::Restraint::UnableToLock, wait: :polynomially_longer, attempts: 5 do |_job, error|
    GitHub.dogstats.increment("pull_request.maintain_tracking_ref_job.retry_exhausted", tags: ["exception_class:#{error.class.name}"])
  end

  def perform(pull_request_id, actor_id, options = {})
    ActiveRecord::Base.connected_to_many([ApplicationRecord::Repositories], role: :reading) do
      pull = PullRequest.find(pull_request_id)
      actor = User.find_by(id: actor_id)
      repository_id = pull.repository_id

      Failbot.push(
        "gh.repo.id": repository_id,
        "gh.pull_request.id": pull.id
      )

      begin
        if FeatureFlag.vexi.enabled?(:restraint_lock_for_maintain_tracking_ref_job, "Repository:#{repository_id}", default: false)
          max_concurrency = begin
            config_value = FeatureFlag.vexi.percentage_of_actors_value_or_raise(:maintain_tracking_ref_job_max_concurrency)  # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage
            config_value > 0 ? config_value.to_i : MAX_CONCURRENT_JOBS
          rescue => e
            MAX_CONCURRENT_JOBS
          end

          restraint = GitHub::Restraint.new
          restraint.lock!(
            "#{RESTRAINT_LOCK_KEY_PREFIX}_#{repository_id}",
            max_concurrency,
            RESTRAINT_LOCK_TTL
          ) do
            pull.maintain_tracking_ref_with_retries(actor, priority: :low)
          end
        else
          pull.maintain_tracking_ref_with_retries(actor, priority: :low)
        end
      rescue GitHub::DGit::ThreepcBusyError => e
        GitHub.logger.info({
          "gh.job.name": "MaintainTrackingRefJob",
          "gh.repo.id": repository_id,
          "gh.pull_request.id": pull.id,
          "gh.pull.number": pull.number,
          "exception.type": e.class.name,
          "exception.message": e.message,
          "actor": actor&.display_login,
        })

        if FeatureFlag.vexi.enabled?(:maintain_tracking_ref_backoff, pull.repository, default: false)
          raise ThreepcBusyBackoffError, e.message
        else
          raise
        end
      end
    end
  end
end
