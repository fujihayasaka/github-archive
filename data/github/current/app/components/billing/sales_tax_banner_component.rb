# typed: strict
# frozen_string_literal: true

class Billing::SalesTaxBannerComponent < ApplicationComponent
  include ApplicationComponent::Rescuable
  include GitHub::Memoizer
  include ResilienceHelper

  rescue_from ActiveRecord::ActiveRecordError, with: :nothing

  LONG_PAST_DATE = DateTime.new(1900, 1, 1)
  FAR_FUTURE_DATE = DateTime.new(2100, 12, 31)

  # The dates of the last tax notification email for each country. Defaults to a date far in the past.
  # The emails are sent to an email list compiled using a DB snapshot on the same day at midnight UTC.
  LAST_TAX_NOTIFICATION_EMAIL_DATE = T.let(Hash.new(LONG_PAST_DATE).merge({
    "US" => DateTime.new(2024, 6, 17, 0, 0, 0).utc,
    "JP" => DateTime.new(2024, 9, 3, 0, 0, 0).utc,
  }), T::Hash[String, DateTime])

  # The dates of when tax collection starts for each country. Defaults to a date far in the future.
  TAX_COLLECTION_START_DATE = T.let(Hash.new(FAR_FUTURE_DATE).merge({
    "US" => DateTime.new(2024, 9, 17, 0, 0, 0).utc,
    "JP" => DateTime.new(2024, 10, 1, 0, 0, 0).utc,
  }), T::Hash[String, DateTime])

  # The dates when we can stop showing the banner for the purposes of notifying the customer of upcoming tax changes
  TAX_NOTIFICATION_BANNER_END_DATE = T.let(Hash.new(FAR_FUTURE_DATE).merge({
    "US" => DateTime.new(2024, 10, 13, 0, 0, 0).utc,
    "JP" => DateTime.new(2024, 10, 13, 0, 0, 0).utc,
  }), T::Hash[String, DateTime])

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

  sig { returns(T::Boolean) }
  memoize def needs_to_validate_address?
    !customer&.has_valid_address_for_tax?
  end

  sig { returns(String) }
  def address_validation_required_title
    case country_code
    when "US"
      "US sales tax and exemption: "
    else
      raise NotImplementedError, "Sales tax banner has no address validation required title for country code #{country_code}"
    end
  end

  sig { returns(String) }
  def address_validation_required_text
    address_type = customer&.contact_for_tax&.address_type || "billing"
    case country_code
    when "US"
      "Please update your #{address_type} information for verification and add a sales tax exemption certificate, if applicable."
    else
      raise NotImplementedError, "Sales tax banner has no address validation required text for country code #{country_code}"
    end
  end

  # Whether or not the account needs to be notified of the upcoming sales tax changes
  sig { returns(T::Boolean) }
  memoize def needs_sales_tax_change_notification?
    last_email_notification_date = T.must(LAST_TAX_NOTIFICATION_EMAIL_DATE[country_code])
    billing_info_created_at = account.billing_contact.created_at || LONG_PAST_DATE
    account_created_at = account.created_at

    # Customers that received an email notification do not need to be notified via banner
    return false if account_created_at < last_email_notification_date &&
      billing_info_created_at < last_email_notification_date

    # Show the banner until we don't need to anymore
    GitHub::Billing.now < TAX_NOTIFICATION_BANNER_END_DATE[country_code]
  end

  sig { returns(String) }
  def sales_tax_change_notification_text
    case country_code
    when "US"
      "Starting August 19th, 2024, we will begin collecting state-mandated sales tax, where and when applicable, from paying customers in the United States."
    when "JP"
      "Starting October 1st, 2024, we will begin collecting Japanese Consumption Tax (JCT), where and when applicable, from paying customers in Japan."
    else
      raise NotImplementedError, "Sales tax banner has no sales tax change notification text for country code #{country_code}"
    end
  end

  sig { returns(String) }
  def sales_tax_changelog_link
    case country_code
    when "US"
      "https://github.blog/changelog/2024-05-28-United-States-Sales-Tax-and-Exemptions-on-your-GitHub-Account/"
    when "JP"
      "https://github.blog/changelog/2024-08-01-japanese-consumption-tax-jct-on-your-github-account/"
    else
      raise NotImplementedError, "Sales tax banner has no sales tax changelog link for country code #{country_code}"
    end
  end

  private

  sig { returns(T.nilable(User)) }
  attr_reader :current_user

  sig { returns(String) }
  memoize def country_code
    customer&.country_code_for_tax_purposes || ""
  end

  sig { returns(T.nilable(Customer)) }
  memoize def customer
    account.customer
  end

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
    return false unless has_permission_to_view_banner?
    return false if account.invoiced?
    return false if account.delegate_billing_to_business?

    # Only display banner for accounts that have payment information via Zuora
    # This would exclude accounts that are partially billed
    return false unless account.payment_method&.valid_payment_token?

    return false unless customer&.in_taxable_country?
    return false if !needs_to_validate_address? && !needs_sales_tax_change_notification?

    true
  end
end
