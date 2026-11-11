# typed: true
# frozen_string_literal: true

class Orgs::ActionsSettings::RulesetsController < Orgs::Controller
  include RulesetViewControllerMethods
  include RulesetEditControllerMethods
  include ApplicationController::VerifiedFetchDependency

  before_action :org_admins_only
  before_action :ensure_trade_restrictions_allows_org_settings_access
  before_action :feature_enabled

  depends_on_clusters ApplicationRecord::ActionsEnvironments,
    only: RulesetViewControllerMethods::GET_CONTROLLER_METHODS +
      (RulesetEditControllerMethods::CONTROLLER_METHODS - [:ruleset_destroy, :ruleset_update])

  allow_verified_fetch only: [:ruleset_update, :ruleset_destroy, :ruleset_validate_value, :ruleset_integration_suggestions, :ruleset_query_metadata]

  sig { override.returns(T.any(Repository, Organization)) }
  protected def current_source
    current_organization
  end

  sig { override.returns(String) }
  protected def index_path
    settings_org_actions_policies_path
  end

  sig { override.returns(Symbol) }
  protected def selected_link
    :organization_actions_settings_policies
  end

  sig { override.returns(T::Array[String]) }
  protected def supported_targets
    %w[actions]
  end

  sig { override.returns(PageStrings) }
  protected def page_strings
    super.merge({
      heading: "Actions policies",
      alphaOrBeta: "beta",
      headingText: "You haven't created any policies",
      rulesetOrPolicy: "policy",
      rulesetsOrPolicies: "policies",
      ruleOrPolicy: "policy",
      rulesOrPolicies: "policies",
      upsellInfoMessage: "whether actions can run in specific contexts.",
      upsellHeaderText: "Protect your most important actions workflows",
    })
  end

  private

  def feature_enabled
    render_404 unless current_organization.feature_enabled_for_source?(:actions_rulesets)
  end

end
