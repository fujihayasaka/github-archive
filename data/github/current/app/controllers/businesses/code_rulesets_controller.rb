# typed: true
# frozen_string_literal: true

class Businesses::CodeRulesetsController < Businesses::BusinessController
  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :business_full_plan_required

  include ApplicationController::VerifiedFetchDependency

  include RulesetViewControllerMethods
  include RulesetEditControllerMethods
  include RulesetInsightsControllerMethods

  allow_verified_fetch only: [:ruleset_update, :ruleset_destroy, :ruleset_validate_value, :ruleset_integration_suggestions, :ruleset_org_suggestions, :ruleset_team_suggestions, :ruleset_history_comparison, :ruleset_available_properties, :ruleset_validate_import]

  depends_on_clusters ApplicationRecord::Authnd,
  only: RulesetViewControllerMethods::CONTROLLER_METHODS + RulesetEditControllerMethods::CONTROLLER_METHODS

  sig { override.returns(RuleEngine::Types::RuleSource) }
  protected def current_source
    this_business
  end

  sig { override.returns(String) }
  protected def index_path
    settings_code_rules_enterprise_path
  end

  sig { override.returns(Symbol) }
  protected def selected_link
    :business_code_rulesets
  end

  sig { override.returns(Symbol) }
  protected def selected_insights_link
    :business_code_rule_insights
  end

  sig { override.returns(T::Array[String]) }
  protected def supported_targets
    %w[branch tag push]
  end

  sig { override.returns(String) }
  protected def layout
    "react_business"
  end

  sig do
    override.returns({
      heading: String,
      alphaOrBeta: T.nilable(String),
      headingText: String,
      rulesetOrPolicy: String,
      rulesetsOrPolicies: String,
      ruleOrPolicy: String,
      rulesOrPolicies: String,
    })
  end
  protected def page_strings
    {
      heading: "Code rulesets",
      alphaOrBeta: nil,
      headingText: "You haven't created any rulesets",
      rulesetOrPolicy: "ruleset",
      rulesetsOrPolicies: "rulesets",
      ruleOrPolicy: "rule",
      rulesOrPolicies: "rules",
    }
  end
end
