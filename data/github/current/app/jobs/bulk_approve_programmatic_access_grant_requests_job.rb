# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class BulkApproveProgrammaticAccessGrantRequestsJob < ApplicationJob
  queue_as :programmatic_access_grants

  retry_on_dirty_exit

  def perform(target, request_ids, actor, entry_point: nil)
    requests = fetch_requests(target, request_ids)

    approved_grants = []
    requests.each do |request|
      grant =
        ActiveRecord::Base.connected_to(role: :writing) do
          ProgrammaticAccessGrantRequest.approve(request, actor, skip_approval_notification: true, entry_point: entry_point)
        end

      approved_grants << grant unless grant.errors.any?
    end

    grouped_accesses = approved_grants.map(&:user_programmatic_access).group_by { |access| access.owner }

    grouped_accesses.each do |owner, accesses|
      AccountMailer.programmatic_access_approved_notice(
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
