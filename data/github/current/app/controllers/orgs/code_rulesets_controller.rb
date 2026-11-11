# typed: true
# frozen_string_literal: true

class Orgs::CodeRulesetsController < Orgs::Controller

  include RulesetViewControllerMethods
  include RulesetEditControllerMethods
  include RulesetInsightsControllerMethods

  include RepositoryRulesets::HashBuilder

  before_action :org_ref_rules_manager_only
  before_action :ensure_trade_restrictions_allows_org_settings_access

  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:ruleset_update, :ruleset_destroy, :ruleset_validate_value, :ruleset_validate_import, :ruleset_integration_suggestions, :ruleset_deferred_target_counts, :ruleset_required_reviewer_suggestions]

  protected

  sig { override.returns(RuleEngine::Types::RuleSource) }
  def current_source
    current_organization
  end

  sig { override.returns(Symbol) }
  def selected_link
    :repo_rulesets
  end

  sig { override.returns(String) }
  def index_path
    organization_rulesets_path
  end

  sig { override.returns(Symbol) }
  def selected_insights_link
    :repo_rule_insights
  end

  sig { override.returns(T::Array[String]) }
  protected def supported_targets
    %w[branch tag push]
  end
end
