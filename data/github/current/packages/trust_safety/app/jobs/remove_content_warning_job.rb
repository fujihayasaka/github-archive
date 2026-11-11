# typed: true
# frozen_string_literal: true

class RemoveContentWarningJob < ApplicationJob
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  queue_as :content_warning

  # Only one job can run at a time for a given network.
  locked_by timeout: 10.minutes, key: ->(job) {
    RemoveContentWarningJob.id_for_repo(job.arguments[0])
  }

  before_enqueue do |job|
    TrustSafety::JobStatus.create(id: RemoveContentWarningJob.id_for_repo(job.arguments[0]))
  end

  def self.status(repo)
    TrustSafety::JobStatus.find(RemoveContentWarningJob.id_for_repo(repo))
  end

  def self.prefix
    "RemoveContentWarningJob"
  end

  def self.id_for_repo(repo)
    "#{prefix}:#{repo&.network_id || repo.id}"
  end

  def perform(
    repo,
    actor:,
    forks:,
    notify_fork_owners:,
    instructions:
  )
    RemoveContentWarningJob.status(repo).track do
      Repository.throttle do
        with_write do
          repo.set_content_warning(
            nil,
            nil,
            nil,
            actor: actor,
            forks: forks,
            notify_fork_owners: notify_fork_owners,
            instructions: instructions,
          )
        end
      end
    end
  end
end
