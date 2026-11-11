# typed: true
# frozen_string_literal: true

class Orgs::SetupView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  include ActionView::Helpers::TagHelper
  include OrganizationTrialsHelper

  attr_reader :plan, :organization, :extend_captcha_timeout

  BILLING_EMAIL_LABELS = { business: "Billing", business_plus: "Work", free: "Contact" }
  DISPLAY_NAME_LABELS = { business: "organization", business_plus: "Enterprise trial", free: "organization", enterprise: "organization" }
  GA_NAME_LABELS = { business: "Team", business_plus: "Enterprise Cloud", free: "Free", enterprise: "Enterprise" }

  def ga_plan_name
    GA_NAME_LABELS[plan.name.to_sym]
  end

  def ga_format_input_tracking(label)
    "Signup funnel setup org,form input,text:#{ga_plan_name} - #{label};"
  end

  def description_text
    return unless is_enterprise_cloud_trial?

    "#{try_enterprise_trial_message}."
  end

  def action_text
    "Set up your #{DISPLAY_NAME_LABELS[plan.name.to_sym]}"
  end

  def button_text
    skip_payment_collection? ? "Next" : "Next: Payment details"
  end

  def form_path(referral_params = {})
    if skip_payment_collection?
      urls.organizations_path
    else
      urls.org_signup_billing_path(referral_params)
    end
  end

  def pricing_experiment_data_attributes(config, params)
    {}
  end

  def form_method
    if skip_payment_collection?
      :post
    else
      :get
    end
  end

  def skip_payment_collection?
    !plan.business? || !GitHub.billing_enabled?
  end

  def collect_billing_email?
    !plan.business? && GitHub.billing_enabled?
  end

  def billing_email_label
    "#{BILLING_EMAIL_LABELS[plan.name.to_sym]} email"
  end

  def is_enterprise_cloud_trial?
    plan.business_plus?
  end

  def login_errors?
    organization&.errors && organization.errors[:login].any?
  end

  def login_value
    organization&.display_login
  end

  def organization_name_hint
    login_errors? || organization.nil? ? "name" : organization&.name
  end

  def email_errors
    organization&.errors && organization.errors[:billing_email]
  end

  def show_captcha?(session)
    return false unless Octocaptcha.new(session, page: :org_create).show_captcha?
    !plan.paid? || is_enterprise_cloud_trial?
  end

  def captcha_timeout
    !!extend_captcha_timeout ? Octocaptcha::HIGHER_BROWSER_LOAD_TIMEOUT : Octocaptcha::DEFAULT_BROWSER_LOAD_TIMEOUT
  end

  def include_filter?
    eligible_orgs_for_ghec_trial(current_user).size > 10
  end

  def show_eligible_existing_org_selector?
    return false unless is_enterprise_cloud_trial?

    eligible_orgs_for_ghec_trial(current_user).size > 0
  end
end
