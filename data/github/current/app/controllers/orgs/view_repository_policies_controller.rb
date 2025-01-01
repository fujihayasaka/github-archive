# typed: strict
# frozen_string_literal: true

class Orgs::ViewRepositoryPoliciesController < Orgs::Controller
  include RulesetViewControllerMethods

  before_action :ensure_logged_in
  before_action :ensure_feature_enabled
  before_action :ensure_org_member

  sig { override.returns(RuleEngine::Types::RuleSource) }
  protected def current_source
    current_organization
  end

  sig { override.returns(String) }
  protected def layout
    "layouts/orgs/rules"
  end

  sig { override.returns(Symbol) }
  protected def selected_link
    :repositories
  end

  sig { override.returns(T::Array[String]) }
  protected def supported_targets
    %w[repository]
  end

  sig { override.returns(T::Boolean) }
  protected def supports_history?
    false
  end

  sig { override.returns(T::Boolean) }
  protected def supports_import_export?
    false
  end

  sig { override.returns(T::Boolean) }
  protected def supports_list_view?
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

  sig { void }
  def ensure_logged_in
    render_404 unless logged_in?
  end

  sig { void }
  def ensure_feature_enabled
    render_404 unless current_organization&.member_privilege_rulesets_enabled? &&
      current_organization&.feature_flag_enabled?(:read_only_policy_view, default: false)
  end

  sig { void }
  def ensure_org_member
    render_404 unless current_organization&.member?(current_user)
  end
end
