# typed: strict
# frozen_string_literal: true

# Enqueued when a UserEmail's state transitions to "verified". Finds any
# BundledLicenseAssignments whose email matches and kicks off the
# per-assignment matching job so that the user is linked to the VSS license.
class Licensing::MatchBundledLicenseAssignmentsForVerifiedEmailJob < ApplicationJob
  queue_as :licensing

  retry_on_dirty_exit

  sig { params(email: String).void }
  def perform(email:)
    Licensing::BundledLicenseAssignment.where(email: email).find_each do |assignment|
      assignment.attempt_to_assign_user_from_business
    end
  end
end
