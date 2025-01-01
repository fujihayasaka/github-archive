# typed: strict
# frozen_string_literal: true

module Licensing::BusinessUserAccount::LicensingDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { BusinessUserAccount }

  # Update the enterprise license cache when the user account is created, updated or removed.
  sig { void }
  def update_business_license_usage
    T.must(business).update_license_usage if business.present?
  end

  private

  sig { void }
  def assign_user_to_bundled_license_assignment
    return if user.nil?
    return unless ActiveRecord::Base.connected_to(role: :reading) do
      business&.has_active_vss_bundle?
    end

    Licensing::SetUserFromEmailsOnBundledLicenseAssignmentJob.perform_later(
      business: T.must(business), user: T.must(user)
    )
  end

  sig { void }
  def unlink_user_from_bundled_license_assignments
    return if user.nil? || business.nil?
    return unless ActiveRecord::Base.connected_to(role: :reading) do
      business&.has_active_vss_bundle?
    end

    Licensing::UnlinkUserFromBundledLicenseAssignmentsJob.perform_later(T.must(user).id, T.must(business).id)
  end
end
