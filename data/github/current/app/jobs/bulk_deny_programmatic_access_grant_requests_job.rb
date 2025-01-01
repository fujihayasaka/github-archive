# typed: true
# frozen_string_literal: true

class BulkDenyProgrammaticAccessGrantRequestsJob < ApplicationJob
  queue_as :programmatic_access_grants

  retry_on_dirty_exit

  BATCH_SIZE = 100

  def perform(target, request_ids, actor)
    requests = fetch_requests(target, request_ids)
    grouped_accesses = {}

    requests.in_batches(of: BATCH_SIZE) do |requests_batch|
      requests_batch.map(&:user_programmatic_access).compact.each do |access|
        grouped_accesses[access.owner] ||= []
        grouped_accesses[access.owner] << access
      end

      with_write { requests_batch.destroy_all }
    end

    grouped_accesses.each do |owner, accesses|
      AccountMailer.programmatic_access_denied_notice(
        accesses,
        owner,
        target
      ).deliver_later
    end
  end

  private

  def fetch_requests(target, request_ids)
    ProgrammaticAccessGrantRequest.
      from_target_and_ids(target, request_ids).
      preload(user_programmatic_access: [:owner])
  end
end
