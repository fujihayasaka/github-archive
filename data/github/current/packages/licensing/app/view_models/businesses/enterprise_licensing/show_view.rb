# typed: true
# frozen_string_literal: true

class Businesses::EnterpriseLicensing::ShowView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  include GitHub::Memoizer
  attr_reader :business, :viewer, :server_license_fetch_failed

  delegate :billing_term_ends_on, :volume_licensing_enabled?,
    :advanced_security_purchased_for_entity?, :advanced_security_seats_for_entity,
    :advanced_security_license, :pending_cycle, to: :business

  def enterprise_or_volume_license_overage?
    enterprise_licenses_overage? || volume_licenses_overage?
  end

  def enterprise_licenses_overage?
    overage_enterprise_licenses > 0
  end

  def volume_licenses_overage?
    overage_volume_licenses > 0
  end

  def total_licenses_overage?
    total_consumed_licenses > total_purchased_licenses_with_overages
  end

  def total_consumed_licenses
    @total_consumed_licenses ||= business.total_consumed_licenses
  end

  def total_purchased_licenses
    @total_purchased_licenses ||= business.total_purchased_licenses
  end

  def total_purchased_licenses_with_overages
    @total_purchased_licenses_with_overages ||= business.total_purchased_licenses_with_overages
  end

  def total_consumed_licenses_percent
    return 0 if total_purchased_licenses <= 0
    percent = (total_consumed_licenses.to_f / total_purchased_licenses_with_overages).round(2)
    (percent * 100).to_i
  end

  def overage_total_licenses
    total_consumed_licenses - total_purchased_licenses
  end

  def consumed_enterprise_licenses
    @consumed_enterprise_licenses ||= business.consumed_enterprise_licenses
  end

  def consumed_enterprise_licenses_percent
    return 0 if available_enterprise_licenses <= 0
    percent = (consumed_enterprise_licenses.to_f / available_enterprise_licenses).round(2)
    (percent * 100).to_i
  end

  def available_enterprise_licenses
    @available_enterprise_licenses ||= business.seats
  end

  def overage_enterprise_licenses
    consumed_enterprise_licenses - available_enterprise_licenses
  end

  def overage_enterprise_licenses_percent
    return 0 if available_enterprise_licenses <= 0
    percent = (overage_enterprise_licenses.to_f / available_enterprise_licenses).round(2)
    (percent * 100).to_i
  end

  def consumed_volume_licenses
    @consumed_volume_licenses ||= business.consumed_volume_licenses
  end

  def consumed_volume_licenses_percent
    return 0 if available_volume_licenses <= 0
    percent = (consumed_volume_licenses.to_f / available_volume_licenses).round(2)
    (percent * 100).to_i
  end

  def available_volume_licenses
    @available_volume_licenses ||= business.purchased_volume_licenses
  end

  def available_volume_licenses_with_overages
    @available_volume_licenses_with_overages ||= business.purchased_volume_licenses_with_overages
  end

  def overage_volume_licenses
    consumed_volume_licenses - available_volume_licenses
  end

  def overage_volume_licenses_percent
    return 0 if available_volume_licenses <= 0
    percent = (overage_volume_licenses.to_f / available_volume_licenses).round(2)
    (percent * 100).to_i
  end

  def installations
    @installations ||= business.enterprise_installations.order(:host_name)
  end

  def installations_user_count
    @installations_user_count ||= installations.map do |installation|
      installation.user_accounts.count
    end.sum
  end

  # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
  def viewer_is_admin?
    @viewer_is_admin ||= business.owner?(viewer)
  end
  # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

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
    features << "GitHub Advanced Security" if license.advanced_security_enabled?
    features.empty? ? "" : "(#{features.join(", ")})"
  end

  def assignments_with_unassigned_users
    @assignments_with_unassigned_users ||= business.bundled_license_assignments.unassigned_user
  end

  def show_assignments_with_unassigned_users_tooltip?
    assignments_with_unassigned_users.any?
  end

  def is_pending_cycle_changing_seats?
    pending_cycle.plan.per_seat? && pending_cycle.seats && pending_cycle.seats > 0
  end

  def pending_cycle_new_price
    plan_cost = pending_cycle.plan_duration == User::BillingDependency::YEARLY_PLAN ? business.plan.yearly_cost : business.plan.cost
    value_in_cents = business.pending_cycle_change.seats * plan_cost * 100
    Billing::Money.new(value_in_cents)
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
    !Copilot::Business.new(business).copilot_disabled?
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
