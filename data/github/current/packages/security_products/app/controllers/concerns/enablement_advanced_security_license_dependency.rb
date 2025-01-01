# typed: true
# frozen_string_literal: true

module EnablementAdvancedSecurityLicenseDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { Orgs::Controller }

  sig { params(org: Organization).returns(Hash) }
  def org_license_payload(org)
    payload = {
      bundled: {
        metered: false,
        allowanceExceeded: false,
        availableSeats: 0,
        remainingSeats: 0,
        consumedSeats: 0,
        exceededSeats: 0,
        hasUnlimitedSeats: false,
      },
      business: nil,
      failedToFetchLicenses: T.let(false, T::Boolean),
    }
    return payload unless org.advanced_security_purchased? || org.code_security_purchased? || org.secret_protection_purchased?

    begin
      if org.advanced_security_products_bundled?
        payload.merge!(bundled_licence_info(org))
      else
        payload.merge!(unbundled_licence_info(org))
        payload.delete(:bundled) # remove fallback info
      end

    rescue AdvancedSecurityLicense::TurboghasError => e
      Failbot.report(e)
      payload[:failedToFetchLicenses] = true
    end

    payload
  end

  private

  sig { params(org: Organization).returns(Hash) }
  def bundled_licence_info(org)
    advanced_security_license = org.advanced_security_license
    ghas_business = advanced_security_license.billable_entity.is_a?(Business) ? advanced_security_license.billable_entity : nil

    allowance_exceeded = advanced_security_license.allowance_exceeded?
    consumed_seats = advanced_security_license.consumed_seats
    exceeded_seats = allowance_exceeded ? (advanced_security_license.seats - consumed_seats).abs : 0

    {
      bundled: {
        metered: org.advanced_security_metered_for_entity?,
        allowanceExceeded: allowance_exceeded,
        availableSeats: advanced_security_license.seats,
        remainingSeats: advanced_security_license.remaining_seats,
        consumedSeats: consumed_seats,
        exceededSeats: exceeded_seats,
        hasUnlimitedSeats: advanced_security_license.unlimited_seats?,
      },
      business: ghas_business&.name,
    }
  end

  sig { params(org: Organization).returns(Hash) }
  def unbundled_licence_info(org)
    advanced_security_license = org.advanced_security_license
    ghas_business = advanced_security_license.billable_entity.is_a?(Business) ? advanced_security_license.billable_entity : nil

    {
      code_security: code_security_licence_info(org),
      secret_protection: secret_protection_license_info(org),
      business: ghas_business&.name,
    }
  end

  sig { params(org: Organization).returns(Hash) }
  def code_security_licence_info(org)
    code_security = org.code_security
    exceeded_seats = code_security.allowance_exceeded? ? (code_security.seats - code_security.seats_used).abs : 0

    {
      metered: org.advanced_security_metered_for_entity?,
      allowanceExceeded: code_security.allowance_exceeded?,
      availableSeats: code_security.seats,
      remainingSeats: code_security.remaining_seats,
      consumedSeats: code_security.seats_used,
      exceededSeats: exceeded_seats,
      hasUnlimitedSeats: code_security.unlimited_seats?,
    }
  end

  sig { params(org: Organization).returns(Hash) }
  def secret_protection_license_info(org)
    secret_protection = org.secret_protection
    exceeded_seats = secret_protection.allowance_exceeded? ? (secret_protection.seats - secret_protection.seats_used).abs : 0

    {
      metered: org.advanced_security_metered_for_entity?,
      allowanceExceeded: secret_protection.allowance_exceeded?,
      availableSeats: secret_protection.seats,
      remainingSeats: secret_protection.remaining_seats,
      consumedSeats: secret_protection.seats_used,
      exceededSeats: exceeded_seats,
      hasUnlimitedSeats: secret_protection.unlimited_seats?,
    }
  end
end
