# typed: true
# frozen_string_literal: true

class Businesses::RepositoryPoliciesController < Businesses::BusinessController

  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :business_full_plan_required

  before_action :member_privilege_rulesets_enabled, except: [:ruleset_available_org_properties]

  include ApplicationHelper
  include ApplicationController::VerifiedFetchDependency

  include RulesetViewControllerMethods
  include RulesetEditControllerMethods

  allow_verified_fetch only: [:ruleset_update, :ruleset_destroy, :ruleset_validate_value, :ruleset_integration_suggestions, :ruleset_org_suggestions, :ruleset_history_comparison, :ruleset_available_properties, :ruleset_deferred_target_counts]

  depends_on_clusters ApplicationRecord::Authnd,
  only: RulesetViewControllerMethods::GET_CONTROLLER_METHODS + RulesetEditControllerMethods::CONTROLLER_METHODS

  depends_on_clusters ApplicationRecord::Repositories,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
  only: [:ruleset_available_org_properties]

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

  sig { override.returns(PageStrings) }
  protected def page_strings
    {
      heading: "Repository policies",
      alphaOrBeta: "beta",
      headingText: "You haven't created any policies",
      rulesetOrPolicy: "policy",
      rulesetsOrPolicies: "policies",
      ruleOrPolicy: "policy",
      rulesOrPolicies: "policies",
      upsellHeaderText: "Protect your most important repositories",
      upsellInfoMessage: "whether members can perform operations on repositories such as delete and transfer.",
    }
  end

  private

  def member_privilege_rulesets_enabled
    render_404 unless current_source.member_privilege_rulesets_enabled?
  end
end
