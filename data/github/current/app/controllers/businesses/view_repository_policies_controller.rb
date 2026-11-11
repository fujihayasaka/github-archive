# typed: strict
# frozen_string_literal: true

class Businesses::ViewRepositoryPoliciesController < Businesses::BusinessController
  before_action :ensure_logged_in
  before_action :business_not_downgraded_to_free_plan_required
  before_action :business_full_plan_required
  before_action :business_member_required

  before_action :member_privilege_rulesets_enabled

  include RulesetViewControllerMethods

  depends_on_clusters ApplicationRecord::Authnd,
  only: RulesetViewControllerMethods::CONTROLLER_METHODS

  sig { override.returns(RuleEngine::Types::RuleSource) }
  protected def current_source
    this_business
  end

  sig { override.returns(Symbol) }
  protected def selected_link
    :business_member_privileges_settings
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

  sig { override.returns(T::Array[String]) }
  protected def supported_targets
    %w[repository]
  end

  sig { override.returns(RuleEngine::DomainAccessorBase[RuleEngine::Types::RuleSource]) }
  protected def ruleset_domain
    Repositories.domain.rulesets
  end

  sig { override.returns(String) }
  protected def layout
    "layouts/businesses/rules"
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
  def ensure_logged_in
    render_404 unless logged_in?
  end

  sig { void }
  def member_privilege_rulesets_enabled
    render_404 unless current_source.member_privilege_rulesets_enabled?
  end

  sig { void }
  def business_member_required
    render_404 unless current_source.member?(current_user)
  end
end
