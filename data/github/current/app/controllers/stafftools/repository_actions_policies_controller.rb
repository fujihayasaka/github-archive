# typed: strict
# frozen_string_literal: true

class Stafftools::RepositoryActionsPoliciesController < StafftoolsController
  before_action :ensure_repo_exists
  before_action :actions_rulesets_enabled

  include ApplicationController::VerifiedFetchDependency

  include RulesetViewControllerMethods

  allow_verified_fetch only: [:ruleset_deferred_target_counts]

  # Added in addition to those depended on in the shared ruleset controller methods
  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::ActionsEnvironments,
    only: RulesetViewControllerMethods::GET_CONTROLLER_METHODS

  sig { override.returns(RuleEngine::Types::RuleSource) }
  protected def current_source
    current_repository
  end

  sig { override.returns(T::Boolean) }
  protected def stafftools?
    true
  end

  sig { override.returns(Symbol) }
  protected def selected_link
    :repository_actions_policies
  end

  sig { override.returns(String) }
  protected def layout
    "layouts/stafftools/repository/overview"
  end

  sig { override.returns(T::Boolean) }
  protected def supports_import_export?
    false
  end

  sig { override.returns(T::Array[String]) }
  protected def supported_targets
    %w[actions]
  end

  sig { override.returns(RuleEngine::DomainAccessorBase[RuleEngine::Types::RuleSource]) }
  protected def ruleset_domain
    Actions.domain.rulesets
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

  sig { void }
  def actions_rulesets_enabled
    render_404 unless GitHub.actions_enabled? && current_source.feature_enabled_for_source?(:actions_rulesets)
  end
end
