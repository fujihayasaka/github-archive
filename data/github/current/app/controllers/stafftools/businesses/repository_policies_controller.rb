# typed: strict
# frozen_string_literal: true

class Stafftools::Businesses::RepositoryPoliciesController < Stafftools::Businesses::BusinessBaseController
  include ApplicationController::VerifiedFetchDependency

  include RulesetViewControllerMethods

  allow_verified_fetch only: [:ruleset_deferred_target_counts]

  before_action :member_privilege_rulesets_enabled

  # Added in addition to those depended on in the shared ruleset controller methods
  depends_on_clusters ApplicationRecord::Ballast,
    only: RulesetViewControllerMethods::GET_CONTROLLER_METHODS

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

  sig { override.returns(RuleEngine::DomainAccessorBase[RuleEngine::Types::RuleSource]) }
  protected def ruleset_domain
    Repositories.domain.rulesets
  end

  sig { override.returns(PageStrings) }
  protected def page_strings
    super.merge({
      heading: "Repository policies",
      alphaOrBeta: "beta",
      headingText: "You haven't created any policies",
      rulesetOrPolicy: "policy",
      rulesetsOrPolicies: "policies",
      ruleOrPolicy: "policy",
      rulesOrPolicies: "policies",
      upsellHeaderText: "Protect your most important repositories",
      upsellInfoMessage: "whether members can perform operations on repositories such as delete and transfer.",
    })
  end

  private

  sig { void }
  def member_privilege_rulesets_enabled
    render_404 unless current_source.member_privilege_rulesets_enabled?
  end
end
