# typed: strict
# frozen_string_literal: true

class Stafftools::Businesses::CodeRulesetsController < Stafftools::Businesses::BusinessBaseController

  before_action :enterprise_rulesets_enabled

  include ApplicationController::VerifiedFetchDependency

  include RulesetViewControllerMethods
  include RulesetInsightsControllerMethods

  # Added in addition to those depended on in the shared ruleset controller methods
  depends_on_clusters ApplicationRecord::Ballast,
    only: RulesetViewControllerMethods::CONTROLLER_METHODS + RulesetInsightsControllerMethods::CONTROLLER_METHODS

  sig { override.returns(RuleEngine::Types::RuleSource) }
  protected def current_source
    this_business
  end

  sig { override.returns(T::Boolean) }
  protected def stafftools?
    true
  end

  sig { override.returns(Symbol) }
  protected def selected_link
    :business_code_rulesets
  end

  sig { override.returns(String) }
  protected def layout
    "layouts/stafftools/business"
  end

  sig { override.returns(T::Array[String]) }
  protected def supported_targets
    %w[branch tag push]
  end

  sig { override.returns(Symbol) }
  protected def selected_insights_link
    :business_code_rule_insights
  end

  sig { void }
  private def enterprise_rulesets_enabled
    render_404 unless current_source.enterprise_rulesets_enabled?
  end

end
