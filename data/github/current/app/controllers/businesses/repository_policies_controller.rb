# typed: true
# frozen_string_literal: true

class Businesses::RepositoryPoliciesController < Businesses::BusinessController

  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :business_full_plan_required

  before_action :member_privilege_rulesets_enabled

  include ApplicationHelper
  include ApplicationController::VerifiedFetchDependency

  include RulesetViewControllerMethods
  include RulesetEditControllerMethods

  allow_verified_fetch only: [:ruleset_update, :ruleset_destroy, :ruleset_validate_value, :ruleset_integration_suggestions, :ruleset_org_suggestions, :ruleset_history_comparison, :ruleset_available_properties]

  depends_on_clusters ApplicationRecord::Authnd,
  only: RulesetViewControllerMethods::CONTROLLER_METHODS + RulesetEditControllerMethods::CONTROLLER_METHODS

  sig { override.returns(RuleEngine::Types::RuleSource) }
  protected def current_source
    this_business
  end

  sig { override.returns(String) }
  protected def index_path
    settings_repository_policies_enterprise_path
  end

  sig { override.returns(Symbol) }
  protected def selected_link
    :business_repository_policies
  end

  sig { override.returns(T::Boolean) }
  protected def supports_import_export?
    false
  end

  sig { override.returns(T::Array[String]) }
  protected def supported_targets
    %w[repository]
  end

  sig { override.returns(String) }
  protected def layout
    "react_business"
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

  private

  def member_privilege_rulesets_enabled
    render_404 unless current_source.member_privilege_rulesets_enabled?
  end
end
