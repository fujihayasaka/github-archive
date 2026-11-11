# typed: strict
# frozen_string_literal: true

class Stafftools::Copilot::CachedBillableOrganizationComponent < ApplicationComponent
  sig { returns(Copilot::Organization) }
  attr_reader :copilot_organization

  sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  attr_reader :cached_organization

  sig { returns(T::Boolean) }
  def render?
    FeatureFlag.vexi.enabled?("copilot_show_cached_billable_organization", @copilot_organization.organization_object, default: false)
  end

  sig { params(copilot_organization: Copilot::Organization).void }
  def initialize(copilot_organization)
    @copilot_organization = copilot_organization

    unless copilot_organization.organization_object.present?
      @cached_organization = T.let({}, T.nilable(T::Hash[Symbol, T.untyped]))
      return
    end

    tracking_id = copilot_organization.analytics_tracking_id
    if tracking_id.blank?
      @cached_organization = T.let({}, T.nilable(T::Hash[Symbol, T.untyped]))
      return
    end

    @cached_organization = T.let(
      fetch_cached_organization(tracking_id),
      T.nilable(T::Hash[Symbol, T.untyped])
    )
  end

  sig { returns(String) }
  def ccr_direct_org_billing_setting
    Copilot::Policies::CcrDirectOrgBilling.value(@copilot_organization)
  end

  sig { returns(Symbol) }
  def ccr_direct_org_billing_label_scheme
    setting = ccr_direct_org_billing_setting
    case setting
    when /\Aenabled/
      :success
    when /\Adisabled/
      :danger
    when /\Ano_policy/
      :accent
    when /\Aunconfigured/
      :secondary
    else
      :secondary
    end
  end

  # Returns PRU (Premium Request Usage) policy status for the organization
  # @return [String] One of: "enabled", "disabled", "N/A (no business)", "Error retrieving policy", or "Error: <message>"
  sig { returns(String) }
  def pru_setting
    # Check if the organization has PRU (Premium Request Usage) enabled
    business = @copilot_organization.business
    return "N/A (no business)" unless business&.customer

    customer_id = T.must(business.customer).id
    billing_client = ::Billing::Platform::Api::Client.new

    policy_response = billing_client.get_overage_policy(
      customer_id: customer_id,
      overage_policy_type: "sku",
      name: "copilot_premium_request",
      is_for_business: true
    )

    return "Error retrieving policy" if policy_response.is_a?(::Billing::Platform::Api::Error)

    policy_response[:overagePolicy][:enabled] == true ? "enabled" : "disabled"
  rescue => e
    "Error: #{e.message}"
  end

  sig { returns(Symbol) }
  def pru_label_scheme
    setting = pru_setting
    case setting
    when "enabled"
      :success
    when "disabled"
      :danger
    else
      :secondary
    end
  end

  private

  sig { params(tracking_id: String).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def fetch_cached_organization(tracking_id)
    response = CopilotLimiter::Twirp.quota_client.get_cached_organization(
      org_tracking_id: tracking_id
    )
    return {} if response.empty?
    response
  rescue TwirpHelper::TwirpError => e
    {}
  end
end
