# typed: strict
# frozen_string_literal: true

class Stafftools::Businesses::RepositoryPoliciesController < Stafftools::Businesses::BusinessBaseController

  before_action :enterprise_rulesets_enabled

  include ApplicationController::VerifiedFetchDependency

  include RulesetViewControllerMethods

  # Added in addition to those depended on in the shared ruleset controller methods
  depends_on_clusters ApplicationRecord::Ballast,
    only: RulesetViewControllerMethods::CONTROLLER_METHODS

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
    :business_repository_policies
  end

  sig { override.returns(T::Boolean) }
  protected def supports_import_export?
    false
  end

  sig { override.returns(String) }
  protected def layout
    "layouts/stafftools/business"
  end

  sig { override.returns(T::Array[String]) }
  protected def supported_targets
    %w[repository]
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
      heading: "Repository policies",
      alphaOrBeta: "beta",
      headingText: "You haven't created any policies",
      rulesetOrPolicy: "policy",
      rulesetsOrPolicies: "policies",
      ruleOrPolicy: "policy",
      rulesOrPolicies: "policies",
    }
  end

  sig { void }
  private def enterprise_rulesets_enabled
    render_404 unless current_source.enterprise_rulesets_enabled?
  end

end
