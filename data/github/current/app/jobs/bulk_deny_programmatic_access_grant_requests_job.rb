# typed: true
# frozen_string_literal: true

class BulkDenyProgrammaticAccessGrantRequestsJob < ApplicationJob
  queue_as :programmatic_access_grants

  retry_on_dirty_exit

  BATCH_SIZE = 100

  def perform(target, request_ids, actor, reason = nil)
    requests = fetch_requests(target, request_ids)

    requests.in_batches(of: BATCH_SIZE) do |requests_batch|
      requests_batch.each do |request|
        ActiveRecord::Base.connected_to(role: :writing) do
          ProgrammaticAccessGrantRequest.deny(request, actor, reason)
        end
      end
    end
  end

  private

  def fetch_requests(target, request_ids)
    ProgrammaticAccessGrantRequest.
      from_target_and_ids(target, request_ids).
      preload(user_programmatic_access: [:owner])
  end
end
