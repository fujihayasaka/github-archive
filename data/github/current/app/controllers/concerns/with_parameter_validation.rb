# typed: true
# frozen_string_literal: true

require "uri"

# Shared validation logic for the 'with' benefit parameter used on the Digital Front Door (DFD) /get_started pages
module WithParameterValidation
  include BusinessesHelper

  ALLOWED_WITH_VALUES = %w[
    advanced-security
    code-security
    copilot-business
    enterprise
    enterprise-and-ado
    risk-assessment
    secret-protection
    ].freeze

  sig { params(value: T.untyped).returns(T::Boolean) }
  def valid_with_param?(value)
    return false unless value.is_a?(String)
    ALLOWED_WITH_VALUES.include?(value)
  end

  sig { params(params: ActionController::Parameters).returns(T.nilable(String)) }
  def extract_with_param(params)
    raw_param = params[:with]
    return nil unless raw_param.is_a?(String)
    return raw_param if valid_with_param?(raw_param)
    nil
  end

  sig { params(params: ActionController::Parameters).returns(T.nilable(Symbol)) }
  def extract_and_validate_intent(params)
    with_param = extract_with_param(params)
    return nil if with_param.blank?

    # Convert hyphenated param to underscore for enum lookup
    intent_symbol = with_param.tr("-", "_").to_sym

    return intent_symbol if BusinessIntent.intents.key?(intent_symbol.to_s)

    nil
  end

  # Extract with parameter from both request query parameters and params (for broader compatibility)
  sig { params(request: ActionDispatch::Request, params: ActionController::Parameters).returns(T.nilable(String)) }
  def extract_with_param_from_request(request, params)
    raw_param = request.query_parameters[:with] if request.query_parameters[:with].present?
    raw_param ||= params[:with] if params[:with].present?
    return nil unless raw_param.is_a?(String)
    return raw_param if valid_with_param?(raw_param)
    nil
  end

  sig { params(path: String, params: ActionController::Parameters).returns(String) }
  def add_with_param_to_path(path, params)
    with_param = extract_with_param(params)
    return path if with_param.blank?

    uri = URI.parse(path)
    query_params = Rack::Utils.parse_query(uri.query || "")
    query_params["with"] = with_param
    uri.query = query_params.any? ? query_params.to_query : nil
    uri.to_s
  end

  sig { params(account: T.any(Organization, Business), params: ActionController::Parameters).returns(String) }
  def with_param_to_url(account, params)
    with_param = extract_with_param(params)
    benefit_path(with_param, account)
  end

  sig { params(account: T.any(Organization, Business), benefit: T.nilable(String)).returns(T::Boolean) }
  def eligible_for_trial_flow?(account, benefit)
    return false unless account.is_a?(Business)
    return false unless benefit == "secret-protection" || benefit == "code-security"
    return false unless FeatureFlag.vexi.enabled?(:ghas_get_started_trial_flow, account, default: false)

    account.eligible_for_self_serve_advanced_security_trial?
  end

  private

  sig { params(with_param: T.nilable(String), account: T.any(Organization, Business)).returns(String) }
  def benefit_path(with_param, account)
    case with_param
    when "enterprise"
      button_enterprise_path(account)
    when "copilot-business"
      button_copilot_business_path(account)
    when "secret-protection"
      button_secret_protection_path(account)
    when "code-security"
      button_code_security_path(account)
    when "advanced-security"
      button_advanced_security_path(account)
    when "enterprise-and-ado"
      button_enterprise_and_ado_path(account)
    when "risk-assessment"
      button_risk_assessment_path(account)
    else
      account_path(account)
    end
  end

  def account_path(account)
    if account.is_a?(Organization)
      urls.user_path(account)
    else
      urls.enterprise_path(account)
    end
  end

  def button_enterprise_path(account)
    if account.is_a?(Business)
      urls.enterprise_path(account, with: "enterprise")
    elsif account.is_a?(Organization)
      urls.settings_org_billing_path(organization_id: account, with: "enterprise")
    end
  end

  def button_copilot_business_path(account)
    if account.is_a?(Business)
      return urls.enterprise_path(account, with: "copilot-business") if account.trial_expired?
      if show_ai_controls?(account)
        urls.copilot_enterprise_ai_controls_enterprise_path(account, with: "copilot-business")
      else
        urls.settings_copilot_enterprise_path(account, with: "copilot-business")
      end
    elsif account.is_a?(Organization)
      urls.settings_org_copilot_path(organization_id: account, with: "copilot-business")
    end
  end

  def button_secret_protection_path(account)
    if account.is_a?(Business)
      return urls.get_started_advanced_security_trial_path(enterprise: account.slug, with: "secret-protection") if eligible_for_trial_flow?(account, "secret-protection")
      urls.security_center_alerts_secret_scanning_enterprise_path(account, with: "secret-protection")
    elsif account.is_a?(Organization)
      if FeatureFlag.vexi.enabled?(:ghas_get_started_trial_flow, account, default: false)
        urls.security_center_assessments_path(org: account, assessmentType: "secret-protection")
      else
        urls.security_center_alerts_secret_scanning_path(org: account, with: "secret-protection")
      end
    end
  end

  def button_code_security_path(account)
    if account.is_a?(Business)
      return urls.get_started_advanced_security_trial_path(enterprise: account.slug, with: "code-security") if eligible_for_trial_flow?(account, "code-security")
      urls.security_center_alerts_code_scanning_enterprise_path(account, with: "code-security")
    elsif account.is_a?(Organization)
      if FeatureFlag.vexi.enabled?(:ghas_get_started_trial_flow, account, default: false)
        urls.security_center_assessments_path(org: account, assessmentType: "code-security")
      else
        urls.security_center_alerts_code_scanning_path(org: account, with: "code-security")
      end
    end
  end

  def button_advanced_security_path(account)
    if account.is_a?(Business)
      urls.settings_security_analysis_enterprise_path(account, with: "advanced-security")
    elsif account.is_a?(Organization)
      urls.settings_org_security_products_path(organization_id: account, with: "advanced-security")
    end
  end

  def button_enterprise_and_ado_path(account)
    if account.is_a?(Business)
      urls.enterprise_path(account, with: "enterprise-and-ado")
    else
      urls.settings_org_billing_path(organization_id: account, with: "enterprise-and-ado")
    end
  end

  def button_risk_assessment_path(account)
    urls.security_center_assessments_path(org: account)
  end

  sig { returns(UrlHelpers) }
  def urls
    T.cast(Class.new { include UrlHelpers }.new, UrlHelpers)
  end
end
