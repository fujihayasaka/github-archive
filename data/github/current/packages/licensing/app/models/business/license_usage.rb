# typed: strict
# frozen_string_literal: true

class Business::LicenseUsage < ApplicationRecord::Domain::Users

  validates_uniqueness_of :business_id
  belongs_to :business

  # Calculate the consumed license count for the business.
  #
  # This updates the attributes for this object but does not save the changes.
  sig { params(business: Business, generated_at: T.nilable(::ActiveSupport::TimeWithZone)).returns(T.self_type) }
  def update_usage(business, generated_at = Time.zone.now)
    self.generated_at = generated_at
    self.consumed_enterprise_licenses = business.license_attributer.consumed_enterprise_licenses
    self.consumed_volume_licenses = business.license_attributer.consumed_volume_licenses

    self
  end

  # Increase the consumed enterprise licenses.
  #
  # This is used during bulk adds of users to increase the count without recalculating
  # for each user that's added.
  sig { params(count: Integer).void }
  def add_consumed_seats(count)
    return if count <= 0

    self.update(consumed_enterprise_licenses: consumed_enterprise_licenses + count, generated_at: Time.now)
  end

  # Returns a cache seed based off generated_at, to be used as a key
  # when caching data that should expire when the license usage changes.
  sig { returns(Integer) }
  def cache_seed
    return 0 if generated_at.blank?

    (generated_at.to_f * 1000).to_i
  end
end
