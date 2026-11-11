# typed: true
# frozen_string_literal: true

class Businesses::ActionsRulesetsController < Businesses::BusinessController
  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :business_full_plan_required
  before_action :feature_enabled
  before_action :ensure_actions_enabled

  include ApplicationController::VerifiedFetchDependency

  include RulesetViewControllerMethods
  include RulesetEditControllerMethods

  allow_verified_fetch only: [:ruleset_update, :ruleset_destroy, :ruleset_validate_value, :ruleset_integration_suggestions, :ruleset_query_metadata]

  depends_on_clusters ApplicationRecord::Authnd,
    ApplicationRecord::ActionsEnvironments,
    only: RulesetViewControllerMethods::GET_CONTROLLER_METHODS + RulesetEditControllerMethods::CONTROLLER_METHODS

  sig { override.returns(RuleEngine::Types::RuleSource) }
  protected def current_source
    this_business
  end

  sig { override.returns(String) }
  protected def index_path
    settings_actions_rules_enterprise_path
  end

  sig { override.returns(Symbol) }
  protected def selected_link
    :business_actions_rulesets
  end

  sig { override.returns(T::Array[String]) }
  protected def supported_targets
    %w[actions]
  end

  sig { override.returns(RuleEngine::DomainAccessorBase[RuleEngine::Types::RuleSource]) }
  protected def ruleset_domain
    Actions.domain.rulesets
  end

  sig { override.returns(String) }
  protected def layout
    "react_business"
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
      protectionsHeading: "Workflow execution protections",
    })
  end

  private

  def feature_enabled
    render_404 unless this_business.feature_enabled_for_source?(:actions_rulesets)
  end

  def ensure_actions_enabled
    render_404 unless GitHub.actions_enabled?
  end
end
