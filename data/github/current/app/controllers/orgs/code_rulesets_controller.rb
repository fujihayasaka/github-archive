# typed: true
# frozen_string_literal: true

class Orgs::CodeRulesetsController < Orgs::Controller

  include RulesetViewControllerMethods
  include RulesetEditControllerMethods
  include RulesetInsightsControllerMethods

  include RepositoryRulesets::HashBuilder

  before_action :org_ref_rules_manager_only
  before_action :ensure_trade_restrictions_allows_org_settings_access

  include ReactHelper
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:ruleset_update, :ruleset_destroy, :ruleset_validate_value, :ruleset_validate_import, :ruleset_integration_suggestions, :ruleset_deferred_target_counts, :ruleset_required_reviewer_suggestions]

  before_action :ensure_org_owns_ruleset, only: [:export_ruleset]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::Spokes,
    only: [:get_workflows_content]

  def get_workflows_content # rubocop:todo GitHub/UseRestfulActions
    type = params.require(:type)
    if type == "repos"
      render json: RulesEngine::WorkflowsHelper.workflow_repo_suggestions(current_organization, params[:q])
    elsif type == "workflows"
      selected_repo = current_organization.repositories.find_by(name: params[:repoName])

      return render status: 200, json: { paths: [] } if selected_repo.nil?

      render json: RulesEngine::WorkflowsHelper.workflow_suggestions(selected_repo)
    elsif type == "sha"
      selected_repo = current_organization.repositories.find_by(name: params[:repoName])
      return render status: 200, json: { sha: nil } if selected_repo.nil?

      ref = params.require(:ref)
      return render status: 400, json: { sha: nil } unless ref.starts_with?("refs/heads/") || ref.starts_with?("refs/tags/")

      sha = selected_repo.refs[ref].try(:sha)
      render json: { sha: sha }
    else
      render_404
    end
  end

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
end
