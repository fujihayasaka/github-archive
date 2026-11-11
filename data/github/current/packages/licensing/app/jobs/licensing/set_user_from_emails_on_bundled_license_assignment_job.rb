# typed: strict
# frozen_string_literal: true

class Licensing::SetUserFromEmailsOnBundledLicenseAssignmentJob < ApplicationJob
  queue_as :licensing
  retry_on_dirty_exit

  discard_on ActiveRecord::RecordNotFound

  sig { params(business: Business, user: User, emails: T.nilable(T::Array[String])).void }
  def perform(business:, user:, emails: nil)
    # Skip the _admin setup account — it should not consume a VSS license.
    # When an EMU enterprise is set up, a {shortcode}_admin account is created
    # whose profile_email matches the real admin's email. Without this guard,
    # SCIM group updates can trigger this job for the _admin user, overwriting
    # the correct user on the BLA.
    return if user.is_first_emu_owner?

    assignment_emails = user.emails.verified.pluck(:email)
    assignment_emails += emails.to_a

    business.bundled_license_assignments.where(email: assignment_emails.compact.uniq).each do |assignment|
      with_write { assignment.update(user_id: user.id) }
    end
  end
end
