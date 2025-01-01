# typed: strict
# frozen_string_literal: true

class Billing::SalesTaxBannerComponent < ApplicationComponent
  extend T::Sig
  include ApplicationComponent::Rescuable
  include GitHub::Memoizer
  include ResilienceHelper

  rescue_from ActiveRecord::ActiveRecordError, with: :nothing

  # The last email notification is expected to be sent out on June 17th, 2024 and will be
  # sent to an email list compiled using a DB snapshot on the same day at midnight UTC.
  LAST_SALES_TAX_EMAIL_NOTIFICATION_DATE = T.let(DateTime.new(2024, 6, 17, 0, 0, 0).utc, Time)

  # Sales tax collection will start on August 19th, 2024. Time unknown so assume end of day.
  # Once started, checkout pages will indicate that sales tax will be collected on eligible accounts.
  SALES_TAX_COLLECTION_START_DATE = T.let(DateTime.new(2024, 8, 20, 0, 0, 0).utc, Time)

  sig { params(account: Billing::Types::Account, current_user: T.nilable(User)).void }
  def initialize(account:, current_user:)
    @current_user = current_user
    @account = account
  end

  sig { returns(Billing::Types::Account) }
  attr_reader :account

  sig { returns(String) }
  def path_to_payment_page
    if account.business?
      settings_billing_tab_enterprise_path(account, tab: :payment_information)
    elsif account.organization?
      settings_org_billing_tab_path(account, tab: "payment_information")
    else
      settings_user_billing_tab_path(tab: "payment_information")
    end
  end

  sig { returns(String) }
  def information_to_update
    to_update_list = []
    to_update_list << "billing" if needs_validated_billing_address?
    to_update_list << "shipping" if needs_validated_shipping_address?
    to_update_list.join(" and ")
  end

  sig { returns(T::Boolean) }
  memoize def needs_to_validate_address?
    needs_validated_billing_address? || needs_validated_shipping_address?
  end

  # Whether or not the account needs a validated billing address on file
  sig { returns(T::Boolean) }
  memoize def needs_validated_billing_address?
    !account.trade_screening_record.validated_for_sales_tax?
  end

  # Whether or not the account needs a validated shipping address on file
  sig { returns(T::Boolean) }
  memoize def needs_validated_shipping_address?
    return false unless account.customer&.shipping_contact.present?
    account.customer&.shipping_contact&.address_validated_at.blank?
  end

  # Whether or not the account needs to be notified of the upcoming sales tax changes
  sig { returns(T::Boolean) }
  memoize def needs_sales_tax_change_notification?
    T.must(account.created_at) >= LAST_SALES_TAX_EMAIL_NOTIFICATION_DATE &&
      T.must(account.created_at) < SALES_TAX_COLLECTION_START_DATE
  end

  private

  sig { returns(T.nilable(User)) }
  attr_reader :current_user

  sig { returns(T::Boolean) }
  def has_permission_to_view_banner?
    if account.is_a?(Business) || account.is_a?(Organization)
      account.adminable_by?(current_user) || T.unsafe(account).billing_manager?(current_user)
    else
      account.adminable_by?(current_user)
    end
  end

  sig { returns(T::Boolean) }
  def render?
    return false unless GitHub.billing_enabled?
    return false unless logged_in?
    return false unless account.feature_enabled?(:display_sales_tax_banner)
    return false unless account.eligible_for_sales_tax?
    return false if !needs_to_validate_address? && !needs_sales_tax_change_notification?
    return false if account.invoiced?
    return false unless has_permission_to_view_banner?
    # Only display the banner at the enterprise-level for enterprise-owned orgs since the billing is managed at the enterprise level
    return false if account.organization? && account.delegate_billing_to_business?
    true
  end
end
