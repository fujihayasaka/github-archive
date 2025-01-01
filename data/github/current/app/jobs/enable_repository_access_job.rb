# typed: true
# frozen_string_literal: true

class EnableRepositoryAccessJob < ApplicationJob
  queue_as :repository_access

  discard_on ActiveJob::DeserializationError do |_job, error|
    Failbot.report(error)
  end

  locked_by timeout: 10.minutes, key: DEFAULT_LOCK_PROC

  before_enqueue do |job|
    repo = job.arguments[0]
    with_write { JobStatus.create(id: EnableRepositoryAccessJob.job_id(repo)) }
  end

  def self.job_id(repo)
    "enable_repository_access_job_#{repo.id}"
  end

  def self.status(repo)
    JobStatus.find(EnableRepositoryAccessJob.job_id(repo))
  end

  def perform(repo, user)
    status = JobStatus.find!(EnableRepositoryAccessJob.job_id(repo))

    status.track do
      with_write { repo.access.enable(user) }
    end
  end
end
