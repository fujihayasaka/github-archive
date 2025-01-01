# typed: true
# frozen_string_literal: true

class RepositoryCloneJob < ApplicationJob
  default_to_write_connection! # rubocop:todo GitHub/JobsDoNotDefaultToWriteConnection

  queue_as :critical

  locked_by timeout: 1.hour, key: -> (job) { job.arguments[1].id }

  # Discard the job if the user or repository are deleted before the job runs
  discard_on ActiveRecord::RecordNotFound

  def perform(source_repo, destination_repo)
    Repository::Clone.from_repo(source_repo: source_repo, destination_repo: destination_repo)
  end
end
