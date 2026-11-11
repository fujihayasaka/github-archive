# typed: strict
# frozen_string_literal: true

class Licensing::SetUserFromBusinessOnBundledLicenseAssignmentJob < ApplicationJob
  queue_as :licensing

  retry_on_dirty_exit

  discard_on ActiveRecord::RecordNotFound

  sig { params(assignment: Licensing::BundledLicenseAssignment).void }
  def perform(assignment:)
    with_write do
      assignment.save! if assignment.set_user_by_verified_emails
    end
  end
end
