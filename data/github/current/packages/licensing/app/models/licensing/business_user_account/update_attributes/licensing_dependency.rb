# typed: true
# frozen_string_literal: true

module Licensing::BusinessUserAccount::UpdateAttributes::LicensingDependency
  extend T::Sig
  extend T::Helpers
  extend ActiveSupport::Concern
  include GitHub::Memoizer

  requires_ancestor { ::BusinessUserAccount::UpdateAttributes }

  private

  # Emit billing events for accounts that are changing from licensed to unlicensed, or vice versa
  sig { params(bua_ids: T::Array[Integer], new_license: Symbol).returns(T::Array[Integer]) }
  def emit_billing_events(bua_ids, new_license)
    successful_account_ids = []
    business_user_accounts.select { |bua| bua_ids.include?(bua.id) }.each do |account|
      if account.changing_licensed_status?(new_license)
        success = account.has_ghec_license? ? account.emit_removed_license_billing_message : account.emit_added_license_billing_message
        successful_account_ids << account.id if success
      else
        # Account is changing licensing type, but not licensed status. No billing event needed.
        successful_account_ids << account.id
      end
    end
    successful_account_ids
  end

  # Returns a hash of licenses mapped to an array of account IDs that require that license. Only contains
  # accounts that require updates.
  sig { returns(T::Hash[Symbol, T::Array[Integer]]) }
  def get_license_updates_hash
    return {} unless can_set_ghec_licenses_for_business?

    accounts_with_license_mismatches.each_with_object({}) do |account, license_updates_hash|
      license_for_account = calculate_license_value_for_account(account)
      license_updates_hash[license_for_account] ||= []
      license_updates_hash[license_for_account] << account.id
    end
  end

  # Business user accounts that have an incorrect license stored. Business is the source of truth.
  sig { returns(T::Set[BusinessUserAccount]) }
  def accounts_with_license_mismatches
    accounts = []
    BusinessUserAccount.ghec_licenses.keys.each do |ghec_license|
      accounts << accounts_missing_license(ghec_license.to_sym)
      accounts << accounts_with_extra_license(ghec_license.to_sym)
    end
    accounts.flatten.uniq.to_set
  end

  # Business user accounts that are missing the given license.
  sig { params(ghec_license: Symbol).returns(T::Array[BusinessUserAccount]) }
  def accounts_missing_license(ghec_license)
    licenses_from_business(ghec_license) - licenses_from_accounts(ghec_license)
  end

  # Business user accounts that have the given license stored, but should not.
  sig { params(ghec_license: Symbol).returns(T::Array[BusinessUserAccount]) }
  def accounts_with_extra_license(ghec_license)
    licenses_from_accounts(ghec_license) - licenses_from_business(ghec_license)
  end

  # The license value for a given account.
  sig { params(account: BusinessUserAccount).returns(Symbol) }
  def calculate_license_value_for_account(account)
    BusinessUserAccount.ghec_licenses.keys.each do |ghec_license|
      return ghec_license.to_sym if licenses_from_business(ghec_license.to_sym).include?(account)
    end
    :unlicensed
  end

  # Finds business user accounts that have a license assigned to them by the business.
  sig { params(ghec_license: Symbol).returns(T::Array[BusinessUserAccount]) }
  def licenses_from_business(ghec_license)
    return unlicensed_user_accounts if ghec_license == :unlicensed

    user_ids = case ghec_license
    when :enterprise_license
      enterprise_license_user_ids
    when :vss_bundle_license
      vss_bundle_license_user_ids
    else
      raise ArgumentError, "Invalid ghec license: #{ghec_license}"
    end
    business_user_accounts.select { |bua| user_ids.include?(bua.user_id) }
  end

  # Finds business user accounts that have a license saved on the business user account.
  sig { params(ghec_license: Symbol).returns(T::Array[BusinessUserAccount]) }
  def licenses_from_accounts(ghec_license)
    business_user_accounts.select { |bua| bua.ghec_license_type == ghec_license }
  end

  # heck if GHEC licenses can be set for business. To prevent trial accounts from being
  # billed, the licenses should not be set yet. Also, they should not be set for business that has
  # not been onboarded to the billing vNext platform.
  memoize def can_set_ghec_licenses_for_business?
    return false if business.trial?
    customer_onboarded_to_billing_vnext?
  end

  # Create billing platform API client instance.
  memoize def billing_client
    ::Billing::Platform::Api::Client.new
  end

  # Billing platform API client response on getting business customer.
  memoize def billing_client_response
    billing_client.get_customer(customer_id: business.customer.id)
  end

  # Check if customer has been onboarded to the billing vNext platform.
  memoize def customer_onboarded_to_billing_vnext?
    return false unless business.metered_plan?
    return false unless business.customer.present?
    return false if billing_client_response.is_a?(Billing::Platform::Api::Error)
    billing_client_response[:customer].present?
  end

  memoize def license_attributer
    Business::LicenseAttributer.new(business)
  end

  memoize def unlicensed_user_accounts
    all_licensed_user_accounts = business_user_accounts.select { |bua| all_license_user_ids.include?(bua.user_id) }
    business_user_accounts - all_licensed_user_accounts
  end

  memoize def vss_bundle_license_user_ids
    license_attributer.bundled_license_assignment_user_ids
  end

  memoize def enterprise_license_user_ids
    all_license_user_ids - vss_bundle_license_user_ids
  end

  memoize def all_license_user_ids
    license_attributer.user_ids
  end
end
