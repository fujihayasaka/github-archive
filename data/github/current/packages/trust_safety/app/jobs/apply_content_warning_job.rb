# typed: true
# frozen_string_literal: true

class ApplyContentWarningJob < ApplicationJob
  class ApplyContentWarningError < StandardError; end

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  queue_as :content_warning

  # Only one job can run at a time for a given network.
  locked_by timeout: 10.minutes, key: ->(job) {
    ApplyContentWarningJob.id_for_repo(job.arguments[0])
  }

  before_enqueue do |job|
    JobStatus.create(id: ApplyContentWarningJob.id_for_repo(job.arguments[0]))
  end

  def self.status(repo)
    JobStatus.find(ApplyContentWarningJob.id_for_repo(repo))
  end

  def self.id_for_repo(repo)
    "ApplyContentWarningJob:#{repo&.network_id || repo.id}"
  end

  def perform(
    repo,
    category,
    sub_category = nil,
    custom_sub_category = nil,
    actor:,
    forks:,
    notify_fork_owners:,
    instructions:
  )
    ApplyContentWarningJob.status(repo).track do
      type = TrustSafety::ContentWarnings.type_for(category)
      if type.nil?
        raise ApplyContentWarningError.new("Invalid content warning category: #{category}")
      end
      Repository.throttle do
        with_write do
          repo.set_content_warning(
            category,
            sub_category,
            custom_sub_category,
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
