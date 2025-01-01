# typed: true
# frozen_string_literal: true

class Repos::RepositoryRulesetController < AbstractRepositoryController
  extend T::Sig

  include BranchesHelper
  include RulesetViewControllerMethods

  before_action :plan_supports_rules

  protected

  sig { override.returns(RuleEngine::Types::RuleSource) }
  def current_source
    current_repository
  end

  sig { override.returns(Symbol) }
  def selected_link
    :repo_source
  end

  sig { override.returns(T::Boolean) }
  def supports_history?
    false
  end

  sig { override.returns(String) }
  def layout
    "layouts/repository/rules"
  end

  sig { override.returns(T::Array[String]) }
  protected def supported_targets
    %w[branch tag push]
  end

  private

  def plan_supports_rules
    render_404 unless current_repository.plan_supports?(:protected_branches)
  end

end
