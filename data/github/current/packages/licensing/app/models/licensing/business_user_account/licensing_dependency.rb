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
  def snapshot_license_state
    Licensing::SnapshotLicensesJob.perform_later(business) if business.present?
  end

  sig { void }
  def assign_user_to_bundled_license_assignment
    return if user.nil?
    return unless ActiveRecord::Base.connected_to(role: :reading) do
      business&.volume_licensing_enabled?
    end

    Licensing::SetUserFromEmailsOnBundledLicenseAssignmentJob.perform_later(
      business: T.must(business), user: T.must(user)
    )
  end
end
