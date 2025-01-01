# typed: strict
# frozen_string_literal: true

class Licensing::SetUserFromBusinessOnBundledLicenseAssignmentJob < ApplicationJob

  queue_as :licensing

  retry_on_dirty_exit

  discard_on ActiveRecord::RecordNotFound

  sig { params(assignment: Licensing::BundledLicenseAssignment).void }
  def perform(assignment:)
    return if assignment.revoked?
    return if assignment.business.nil?

    user = business_user_by_verified_email(assignment)
    with_write { assignment.update(user: user) } if assignment.user_id != user&.id
  end

  private

  sig { params(assignment: Licensing::BundledLicenseAssignment).returns(T.nilable(User)) }
  def business_user_by_verified_email(assignment)
    business = assignment.business

    if business&.enterprise_managed?
      business_user_account = business.dotcom_users_from_emails([business.add_emu_shortcode_to_emails(assignment.email)]).values.first
      return business_user_account&.user if business_user_account&.user

      return unless business.external_provider_enabled?
      business.external_provider&.external_identities&.by_scim_username(assignment.email)&.first&.user
    else
      business_user_account = business&.dotcom_users_from_emails([assignment.email]).values.first
      business_user_account&.user
    end
  end
end
