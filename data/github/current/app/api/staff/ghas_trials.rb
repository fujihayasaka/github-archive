# typed: true
# frozen_string_literal: true

# All endpoints added for Incident response
class Api::Staff::GhasTrials < Api::Staff::App

  before do
    deliver_error! 404 if GitHub.enterprise?
  end

  # rubocop:todo GitHub/ControlAccess
  post "/staff/ghas_trial/enterprises/:enterprise_id", operation_id: :internal do # rubocop:disable GitHub/DuplicateRoutesAreDefinedTogether
    @route_owner = "@github/octogrowth"
    enterprise = find_enterprise!
    validate_advanced_security_enabled(enterprise)

    data = attr(receive(Hash), :number_of_days, :sfdc_poc_url)
    number_of_days = data[:number_of_days]
    deliver_error! 400, message: "Invalid number of days" unless allowed_trial_number_of_days?(number_of_days)

    sfdc_poc_url = data[:sfdc_poc_url] || ""
    if FeatureFlag.vexi.enabled?(:advanced_security_ghas_trial_require_sfdc_poc_url, default: false)
      deliver_error!(400, message: "sfdc_poc_url is required") if sfdc_poc_url.blank?
    end

    ghas_trial = new_ghas_trial(billable_entity: enterprise)
    ghas_trial.enable(number_of_days, sfdc_poc_url:)
    deliver_empty status: 201
  end
  # rubocop:enable GitHub/ControlAccess

  delete "/staff/ghas_trial/enterprises/:enterprise_id", operation_id: :internal do # rubocop:todo GitHub/ControlAccess
    @route_owner = "@github/octogrowth"
    enterprise = find_enterprise!
    enabled = enterprise.advanced_security_trial_enabled_for_entity?
    deliver_error! 400, message: "Trial already disabled" unless enabled

    ghas_trial = new_ghas_trial(billable_entity: enterprise)
    ghas_trial.disable
    deliver_empty status: 200
  end

  # rubocop:todo GitHub/ControlAccess
  patch "/staff/ghas_trial/enterprises/:enterprise_id", operation_id: :internal do # rubocop:disable GitHub/DuplicateRoutesAreDefinedTogether
    @route_owner = "@github/octogrowth"
    enterprise = find_enterprise!
    enabled = enterprise.advanced_security_trial_enabled_for_entity?
    deliver_error! 400, message: "Trial already disabled, use the POST request to enable trial again" unless enabled

    data = attr(receive(Hash), :extended_number_of_days)
    extended_number_of_days = data[:extended_number_of_days]

    ghas_trial = new_ghas_trial(billable_entity: enterprise)
    ghas_trial.prolong(extended_number_of_days)
    deliver_empty status: 200
  end
  # rubocop:enable GitHub/ControlAccess

  get "/staff/ghas_trial/enterprises/:enterprise_id", operation_id: :internal do # rubocop:todo GitHub/ControlAccess
    @route_owner = "@github/octogrowth"
    enterprise = find_enterprise!
    payload = ghas_trial_enabled_payload(enterprise)
    deliver_raw payload, status: 200
  end

  # rubocop:todo GitHub/ControlAccess
  post "/staff/ghas_trial/organizations/:organization_id", operation_id: :internal do # rubocop:disable GitHub/DuplicateRoutesAreDefinedTogether
    @route_owner = "@github/octogrowth"
    org = find_org!
    payload = validate_org_from_business(org)
    return deliver_raw payload, status: 400 if payload
    validate_advanced_security_enabled(org)

    data = attr(receive(Hash), :number_of_days, :sfdc_poc_url)
    number_of_days = data[:number_of_days]
    deliver_error! 400, message: "Invalid number of days" unless allowed_trial_number_of_days?(number_of_days)

    sfdc_poc_url = data[:sfdc_poc_url] || ""
    if FeatureFlag.vexi.enabled?(:advanced_security_ghas_trial_require_sfdc_poc_url, default: false)
      deliver_error!(400, message: "sfdc_poc_url is required") if sfdc_poc_url.blank?
    end

    ghas_trial = new_ghas_trial(billable_entity: org)
    ghas_trial.enable(number_of_days, sfdc_poc_url:)
    deliver_empty status: 201
  end
  # rubocop:enable GitHub/ControlAccess

  # rubocop:todo GitHub/ControlAccess
  delete "/staff/ghas_trial/organizations/:organization_id", operation_id: :internal do
    @route_owner = "@github/octogrowth"
    org = find_org!
    payload = validate_org_from_business(org)
    return deliver_raw payload, status: 400 if payload

    enabled = org.advanced_security_trial_enabled_for_entity?
    deliver_error! 400, message: "Trial already disabled" unless enabled

    ghas_trial = new_ghas_trial(billable_entity: org)
    ghas_trial.disable
    deliver_empty status: 200
  end
  # rubocop:enable GitHub/ControlAccess

  # rubocop:todo GitHub/ControlAccess
  patch "/staff/ghas_trial/organizations/:organization_id", operation_id: :internal do # rubocop:disable GitHub/DuplicateRoutesAreDefinedTogether
    @route_owner = "@github/octogrowth"
    org = find_org!
    payload = validate_org_from_business(org)
    return deliver_raw payload, status: 400 if payload

    enabled = org.advanced_security_trial_enabled_for_entity?
    deliver_error! 400, message: "Trial already disabled, use the POST request to enable trial again" unless enabled

    data = attr(receive(Hash), :extended_number_of_days)
    extended_number_of_days = data[:extended_number_of_days]

    ghas_trial = new_ghas_trial(billable_entity: org)
    ghas_trial.prolong(extended_number_of_days)
    deliver_empty status: 200
  end
  # rubocop:enable GitHub/ControlAccess

  get "/staff/ghas_trial/organizations/:organization_id", operation_id: :internal do # rubocop:todo GitHub/ControlAccess
    @route_owner = "@github/octogrowth"
    org = find_org!
    payload = validate_org_from_business(org)
    return deliver_raw payload, status: 400 if payload

    payload = ghas_trial_enabled_payload(org)
    deliver_raw payload, status: 200
  end

  def new_ghas_trial(billable_entity:)
    EnterpriseCloudOnboard::GhasTrial.new(actor: User.ghost, billable_entity: billable_entity, api_access: true)
  end

  def ghas_trial_enabled_payload(billable_entitiy)
    trial_enabled = billable_entitiy.advanced_security_trial_enabled_for_entity?
    ghas_enabled = billable_entitiy.advanced_security_purchased_for_entity?
    payload = { ghas_trial: trial_enabled, ghas_enabled: ghas_enabled }

    if trial_enabled
      expires_at = new_ghas_trial(billable_entity: billable_entitiy).expires_at
      payload[:expires_at] = expires_at
    end

    if trial_enabled || ghas_enabled
      ghas_seats = billable_entitiy.advanced_security_license.seats
      payload[:ghas_seats] = ghas_seats
    end
    payload
  end

  def validate_advanced_security_enabled(billable_entity)
    if billable_entity.advanced_security_trial_enabled_for_entity?
      deliver_error! 400, message: "Trial already enabled"
    elsif billable_entity.advanced_security_purchased_for_entity?
      deliver_error! 400, message: "Advanced Security already enabled"
    end
  end

  def validate_org_from_business(org)
    return if org.organization? && !org.delegate_billing_to_business?

    {
      message: "cannot manage ghas on this organization due to being a member of an enterprise. Please make the enablement request on the enterprise endpoint.",
      enterprise: org.business&.slug,
    }
  end

  def allowed_trial_number_of_days?(number_of_days)
    return unless number_of_days
    return unless number_of_days.to_i.between?(1, 90)
    true
  end
end
