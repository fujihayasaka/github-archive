# typed: true
# frozen_string_literal: true

class Orgs::RepositoryPoliciesController < Orgs::Controller

  include RulesetViewControllerMethods
  include RulesetEditControllerMethods
  include ApplicationController::VerifiedFetchDependency

  before_action :org_admins_only
  before_action :ensure_trade_restrictions_allows_org_settings_access

  before_action :ensure_feature_enabled

  allow_verified_fetch only: [:ruleset_update, :ruleset_destroy, :ruleset_validate_value]

  sig { override.returns(RuleEngine::Types::RuleSource) }
  protected def current_source
    current_organization
  end

  sig { override.returns(String) }
  protected def index_path
    settings_org_repository_policies_path
  end

  sig { override.returns(Symbol) }
  protected def selected_link
    :repository_policies
  end

  sig { override.returns(T::Array[String]) }
  protected def supported_targets
    %w[repository]
  end

  sig { override.returns(T::Boolean) }
  protected def supports_import_export?
    false
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

  def ensure_feature_enabled
    render_404 if !current_organization.member_privilege_rulesets_enabled?
  end

end
