# typed: true
# frozen_string_literal: true

class RepositoryCloneJob < ApplicationJob
  queue_as :critical

  locked_by timeout: 1.hour, key: -> (job) { job.arguments[1].id }

  # Discard the job if the user or repository are deleted before the job runs
  discard_on ActiveRecord::RecordNotFound

  def perform(source_repo, destination_repo)
    with_write { Repository::Clone.from_repo(source_repo: source_repo, destination_repo: destination_repo) }
  end
end
