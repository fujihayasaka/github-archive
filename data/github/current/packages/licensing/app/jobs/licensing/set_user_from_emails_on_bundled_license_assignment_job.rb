# typed: strict
# frozen_string_literal: true

class Licensing::SetUserFromEmailsOnBundledLicenseAssignmentJob < ApplicationJob
  extend T::Sig

  queue_as :licensing
  retry_on_dirty_exit

  discard_on ActiveRecord::RecordNotFound

  sig { params(business: Business, user: User, emails: T.nilable(T::Array[String])).void }
  def perform(business:, user:, emails: nil)
    assignment_emails = user.emails.verified.pluck(:email)
    assignment_emails += emails.to_a

    business.bundled_license_assignments.where(email: assignment_emails.compact.uniq).each do |assignment|
      with_write { assignment.update(user_id: user.id) }
    end
  end
end
