# typed: true
# frozen_string_literal: true

class Businesses::EnterpriseLicensing::ShowView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  include GitHub::Memoizer
  attr_reader :business, :viewer, :server_license_fetch_failed

  delegate :billing_term_ends_on, :advanced_security_purchased_for_entity?,
    :advanced_security_seats_for_entity, :advanced_security_license, to: :business

  def installations
    @installations ||= business.enterprise_installations.order(:host_name)
  end

  def installations_user_count
    @installations_user_count ||= installations.map do |installation|
      installation.user_accounts.count
    end.sum
  end

  def non_metered_server_licenses
    @non_metered_server_licenses ||= fetch_server_licenses
  end

  def fetch_server_licenses
    @server_license_fetch_failed = false
    return [] unless business.enterprise_web_business_id.present?
    GitHub::EnterpriseWeb::License.all(business.enterprise_web_business_id).sort_by(&:expires_at)
  rescue Faraday::Error
    @server_license_fetch_failed = true
    []
  end

  def server_license_seats_descriptor(license)
    if license.unlimited?
      "Unlimited"
    else
      license.seats
    end
  end

  def server_license_features_descriptor(license)
    features = []
    if license.advanced_security_enabled?
      features << "GitHub Advanced Security"
    else
      features << "Code Security" if license.code_security_enabled?
      features << "Secret Protection" if license.secret_protection_enabled?
    end
    features.empty? ? "" : "(#{features.join(", ")})"
  end

  def assignments_with_unassigned_users
    @assignments_with_unassigned_users ||= business.bundled_license_assignments.unassigned_user
  end

  def show_assignments_with_unassigned_users_tooltip?
    assignments_with_unassigned_users.any?
  end

  def external_groups_count
    @external_groups_count ||= business.external_provider&.external_groups&.not_deleted&.count || 0
  end

  memoize def copilot_standalone_seat_count
    Copilot::Businesses::SeatManagement.copilot_standalone_seat_count(business)
  end

  memoize def copilot_standalone_seat_cost
    copilot_standalone_seat_count * 19.0
  end

  memoize def copilot_enterprise_teams
    business.enterprise_teams.active.filter_by_assignment_type(:copilot)
  end

  def has_azure_sub?
    log_billing_details(business.customer&.azure_subscription_id.present?, __method__)
  end

  def is_metered_billable?
    log_billing_details(business.enterprise_agreements.active.any?, __method__)
  end

  def can_purchase_copilot_standalone_licenses?
    log_billing_details(is_billable?, :copilot_billable?)
  end

  memoize def is_billable?
    Copilot::Business.new(business).copilot_billable?
  end

  def has_copilot_enabled?
    Copilot::Business.new(business).copilot_enabled?
  end

  sig { returns(T::Boolean) }
  def invoiced_self_serve_eligible?
    business.feature_enabled?(:ghe_sales_serve_renewals) && business.invoiced? && business.sales_managed_subscription_self_serve_eligible? && !business.past_due_invoice?
  end

  sig { returns(String) }
  def advanced_security_valid_until_text
    formatted_date = billing_term_ends_on.strftime("%B %-d, %Y")
    return "Billing date on #{formatted_date}" if business.advanced_security_metered_for_entity?
    "Valid until #{formatted_date} (includes support and updates)"
  end

  private

  def log_billing_details(value, method_name)
    return value unless GitHub.flipper[:copilot_business_billable_logging].enabled?(business)

    GitHub.logger.info("Copilot standalone billable details", {
      "gh.business.id" => business.id,
      "gh.copilot.business.billing.method_name" => method_name,
      "gh.copilot.business.billing.value" => value
    })

    value
  end
end
