# typed: true
# frozen_string_literal: true

module EnablementAdvancedSecurityLicenseDependency
  extend ActiveSupport::Concern
  extend T::Sig
  extend T::Helpers

  requires_ancestor { Orgs::Controller }

  sig { params(org: Organization).returns(Hash) }
  def org_license_payload(org)
    payload = {
      allowanceExceeded: false,
      remainingSeats: 0,
      consumedSeats: 0,
      exceededSeats: 0,
      hasUnlimitedSeats: false,
      business: nil,
      failedToFetchLicenses: T.let(false, T::Boolean),
    }
    return payload unless org.advanced_security_purchased?

    begin
      advanced_security_license = org.advanced_security_license
      ghas_business = advanced_security_license.billable_entity.is_a?(Business) ? advanced_security_license.billable_entity : nil

      allowance_exceeded = advanced_security_license.allowance_exceeded?
      consumed_seats = advanced_security_license.consumed_seats
      exceeded_seats = allowance_exceeded ? (advanced_security_license.seats - consumed_seats).abs : 0

      payload.merge!({
        allowanceExceeded: allowance_exceeded,
        remainingSeats: advanced_security_license.remaining_seats,
        consumedSeats: consumed_seats,
        exceededSeats: exceeded_seats,
        hasUnlimitedSeats: advanced_security_license.unlimited_seats?,
        business: ghas_business&.name,
      })
    rescue AdvancedSecurityLicense::TurboghasError => e
      Failbot.report(e)
      payload[:failedToFetchLicenses] = true
    end

    payload
  end
end
