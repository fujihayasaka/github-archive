# typed: true
# frozen_string_literal: true

class Api::Staff::CopilotTrials < Api::Staff::App
  before do
    deliver_error! 404 if GitHub.enterprise?
    deliver_error! 404 if GitHub.multi_tenant_enterprise?
    deliver_error! 404 unless current_user.feature_enabled?(:copilot_trials_staff_api)
  end

  get "/staff/copilot_trials/organizations/:org", operation_id: :internal do # rubocop:todo GitHub/ControlAccess
    @route_owner = "@github/copilot"
    org = find_org_by_login
    deliver_error! 404 unless org.present?

    copilot_plan = params.fetch(:copilot_plan, "enterprise")

    deliver_raw trial_eligibility_payload(org, copilot_plan), status: 200
  end

  # rubocop:disable GitHub/DuplicateRoutesAreDefinedTogether
  post "/staff/copilot_trials/organizations/:organization_id", operation_id: :internal do # rubocop:todo GitHub/ControlAccess
    @route_owner = "@github/copilot"
    org = find_org!

    payload = validate_org_from_business(org)
    return deliver_raw payload, status: 400 if payload

    data = attr(receive(Hash), :copilot_plan, :trial_length_in_days)
    copilot_plan = data[:copilot_plan]
    trial_length_in_days = data[:trial_length_in_days]

    deliver_error! 400, message: "Invalid copilot plan" unless copilot_plan == "enterprise"
    deliver_error! 400, message: "Invalid number of days" unless allowed_trial_length_in_days?(trial_length_in_days)

    if trial = find_trial(org)
      return deliver_raw trial_payload(trial), status: 200
    end

    begin
      trial = Copilot::BusinessTrial.create_trial!(
        org,
        current_user,
        trial_length: trial_length_in_days,
        copilot_plan: copilot_plan,
      )

      T.must(Copilot::Organization.new(org).copilot_business).copilot_for_dotcom_no_policy!

      deliver_raw trial_payload(trial), status: 201
    rescue ActiveRecord::ActiveRecordError => e
      deliver_error! 422, message: e.message
    end
  end

  # rubocop:disable GitHub/DuplicateRoutesAreDefinedTogether
  patch "/staff/copilot_trials/organizations/:organization_id", operation_id: :internal do # rubocop:todo GitHub/ControlAccess
    @route_owner = "@github/copilot"
    org = find_org!
    trial = find_trial(org)

    deliver_error! 404, message: "Trial does not exist for this org" unless trial.present?

    data = attr(receive(Hash), :trial_length_in_days, :action)
    trial_length_in_days = data[:trial_length_in_days]
    action = data[:action] || "extend"

    if action == "extend" && trial.extend_trial!(current_user, trial_length_in_days)
      deliver_raw trial_payload(trial.reload), status: 200
    elsif action == "convert_to_enterprise"
      if trial.trialable.business.nil?
        deliver_error! 422, message: "Copilot Enterprise Trial can only be for an organization that is part of an enterprise"
      elsif !trial.can_be_converted_to_copilot_enterprise_trial?
        deliver_error! 422, message: "Trial cannot be converted to Copilot Enterprise"
      elsif trial.trialable_business_already_on_copilot_enterprise?
        deliver_error! 422, message: "This organization's enterprise is already on Copilot Enterprise"
      elsif trial.trialable.business.present? && Copilot::BusinessTrial.existing_trial_in_org_has_different_plan?(org, "enterprise") && !trial.trialable.business.feature_enabled?(:copilot_mixed_licenses)
        deliver_error! 422, message: "Copilot Trial must be of the same type as existing organization trials in the enterprise"
      elsif !trial.trialable_is_copilot_billable?
        deliver_error! 422, message: "This organization is not billable for GitHub Copilot"
      end

      trial.convert_trial!(current_user, new_trial_length: trial_length_in_days, new_copilot_plan: "enterprise")

      deliver_raw trial_payload(trial.reload), status: 200
    else
      deliver_error! 422, message: "Trial cannot be extended or converted to Copilot Enterprise"
    end
  end

  delete "/staff/copilot_trials/organizations/:organization_id", operation_id: :internal do # rubocop:todo GitHub/ControlAccess
    @route_owner = "@github/copilot"
    org = find_org!
    trial = find_trial(org)

    deliver_error! 404, message: "Trial does not exist for this org" unless trial.present?
    deliver_error! 409, message: "Trial cannot be canceled as it is #{trial.state}" unless trial.cancelable?

    trial.cancel!

    deliver_empty status: 200
  end

  private

  def find_trial(org)
    Copilot::BusinessTrial.for_organization(org)
  end

  def trial_eligibility_payload(org, copilot_plan)
    trial = find_trial(org)
    payload = Hash.new

    # Set default values
    payload[:is_eligible] = false
    payload[:ineligible_reason] = ""
    payload[:trial_copilot_plan] = nil
    payload[:trial_ends_at] = nil
    payload[:trial_state] = nil
    payload[:organization_id] = org.id

    if trial.present?
      payload.merge!(
        ineligible_reason: "Trial already exists and is in #{trial.state} state",
        trial_copilot_plan: trial.copilot_plan,
        trial_ends_at: trial.ends_at,
        trial_state: trial.state,
      )
      return payload
    elsif Copilot::BusinessTrial.existing_trial_in_org_has_different_plan?(org, copilot_plan)
      payload.merge!(
        ineligible_reason: "Copilot #{copilot_plan.capitalize} Trial can only be created if " \
                           "existing organization trials in the enterprise are the same type",
      )
      return payload
    end

    reason = ""
    if copilot_plan == "enterprise"
      reason = if org.business.nil?
        "Standalone orgs are not eligible for Copilot Enterprise trials"
      elsif business_already_on_copilot_enterprise?(org.business)
        "Org's business is already on Copilot Enterprise (via beta or plan)"
      elsif !Copilot::Organization.new(org).copilot_billable?
        "Org is not Copilot billable"
      else
        ""
      end
    end

    payload.merge!(is_eligible: reason.empty?, ineligible_reason: reason)
    payload
  end

  def trial_payload(trial)
    {
      trial_copilot_plan: trial.copilot_plan,
      trial_ends_at: trial.pending? ? nil : trial.ends_at,
      total_days_in_trial: trial.trial_length,
    }
  end

  def validate_org_from_business(org)
    return if org.organization? && org.business.present?

    { message: "Cannot access Copilot Enterprise trial for standalone orgs" }
  end

  def allowed_trial_length_in_days?(trial_length_in_days)
    return unless trial_length_in_days
    return unless trial_length_in_days.to_i.between?(1, 90)
    true
  end

  def business_already_on_copilot_enterprise?(business)
    copilot_business = Copilot::Business.new(business)
    copilot_business.copilot_plan_enterprise? || business.feature_enabled?(:copilot_for_enterprise)
  end
end
