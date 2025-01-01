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

  before_action :ensure_org_owns_ruleset, only: [:export_ruleset]

  # FF is passed to every action because add_client_feature_flag is ignored on soft-nav,
  # so we need it in the index action so it's available on the show & new actions
  before_action :add_client_picker_ff

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

  private

  sig { void }
  def ensure_org_owns_ruleset
    render_404 unless current_organization.rulesets.find_by(id: params[:id]&.to_i).present?
  end

  sig { void }
  def add_client_picker_ff
    add_client_feature_flag [:repos_picker_in_ruleset]
  end
end
