# typed: true
# frozen_string_literal: true

class Stafftools::RepositoryRulesController < StafftoolsController

  before_action :ensure_repo_exists

  include ReactHelper
  include BranchesHelper
  include ApplicationController::VerifiedFetchDependency

  include RulesetViewControllerMethods
  include RulesetInsightsControllerMethods

  allow_verified_fetch only: [:ruleset_deferred_target_counts]

  # Added in addition to those depended on in the shared ruleset controller methods
  depends_on_clusters ApplicationRecord::Ballast,
    only: RulesetViewControllerMethods::CONTROLLER_METHODS + RulesetInsightsControllerMethods::CONTROLLER_METHODS

  protected

  sig { override.returns(RuleEngine::Types::RuleSource) }
  def current_source
    current_repository
  end

  sig { override.returns(Symbol) }
  def selected_link
    :repository_rules
  end

  sig { override.returns(String) }
  def layout
    "layouts/stafftools/repository/overview"
  end

  sig { override.returns(Symbol) }
  def selected_insights_link
    :repository_rule_insights
  end

  sig { override.returns(T::Boolean) }
  def stafftools?
    true
  end

  sig { override.returns(T::Array[String]) }
  protected def supported_targets
    %w[branch tag push]
  end
end
