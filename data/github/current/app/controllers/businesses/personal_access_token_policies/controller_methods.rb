# typed: strict
# frozen_string_literal: true

module Businesses::PersonalAccessTokenPolicies::ControllerMethods
  sig { params(business: Business, actor: User, params: ActionController::Parameters).returns([Symbol, String]) }
  def set_restrict_access_configuration(business, actor, params)
    case params[:restrict_access]
    when "enable"
      business.restrict_personal_access_tokens(actor: actor)
      [:notice, "Fine-grained personal access tokens will no longer have access to your enterprise."]
    when "disable"
      business.permit_personal_access_tokens(actor: actor)
      [:notice, "Fine-grained personal access tokens are now permitted to access your enterprise."]
    when "reset"
      business.reset_personal_access_tokens_restriction(actor: actor)
      [:notice, "Organization administrators can restrict or permit access via fine-grained personal access tokens."]
    else
      [:error, "Unknown option provided."]
    end
  end

  sig { params(business: Business, actor: User, params: ActionController::Parameters).returns([Symbol, String]) }
  def set_restrict_legacy_access_configuration(business, actor, params)
    case params[:restrict_legacy_access]
    when "enable"
      business.restrict_legacy_personal_access_tokens(actor: actor)
      [:notice, "Personal access tokens (classic) will no longer have access to your enterprise."]
    when "disable"
      business.permit_legacy_personal_access_tokens(actor: actor)
      [:notice, "Personal access tokens (classic) are now permitted to access your enterprise."]
    when "reset"
      business.reset_legacy_personal_access_tokens_restriction(actor: actor)
      [:notice, "Organization administrators can restrict or permit access via personal access tokens (classic)."]
    else
      [:error, "Unknown option provided."]
    end
  end

  sig { params(business: Business, actor: User, pat_type: ProgrammaticAccessTokenType, maximum_lifetime_days: Integer, exemption_enabled: T::Boolean, missing_issue_date_exemption_enabled: T::Boolean).returns([Symbol, String]) }
  def set_maximum_lifetime_configuration(business, actor, pat_type, maximum_lifetime_days, exemption_enabled = false, missing_issue_date_exemption_enabled = false)
    lifetime_configuration = ProgrammaticAccessTokenLifetimeConfiguration.new(business, pat_type)
    lifetime_configuration.set_maximum_lifetime_configuration(actor, maximum_lifetime_days, exemption_enabled, missing_issue_date_exemption_enabled)

    [:notice, "Personal access tokens expiration policy updated"]
  rescue Configurable::PersonalAccessTokenExpirationLimit::ConfigurationError => e
    [:error, e.message]
  end

  sig { params(business: Business, actor: User, pat_type: ProgrammaticAccessTokenType).returns([Symbol, String]) }
  def disable_maximum_lifetime_configuration(business, actor, pat_type)
    lifetime_configuration = ProgrammaticAccessTokenLifetimeConfiguration.new(business, pat_type)
    lifetime_configuration.disable_personal_access_token_expiration_limit(actor)

    [:notice, "Personal access tokens expiration policy disabled"]
  end
end
