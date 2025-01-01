# typed: true
# frozen_string_literal: true

class Businesses::MemberPrivilegeRulesetsController < Businesses::BusinessController
  extend T::Sig

  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :business_full_plan_required

  before_action :enterprise_rulesets_enabled

  include ApplicationHelper
  include ApplicationController::VerifiedFetchDependency

  include RulesetViewControllerMethods
  include RulesetEditControllerMethods

  allow_verified_fetch only: [:ruleset_update, :ruleset_destroy, :ruleset_validate_value, :ruleset_integration_suggestions, :ruleset_org_suggestions, :ruleset_available_properties]

  depends_on_clusters ApplicationRecord::Authnd,
  only: RulesetViewControllerMethods::CONTROLLER_METHODS + RulesetEditControllerMethods::CONTROLLER_METHODS

  sig { override.returns(RuleEngine::Types::RuleSource) }
  protected def current_source
    this_business
  end

  sig { override.returns(String) }
  protected def index_path
    settings_member_privilege_rules_enterprise_path
  end

  sig { override.returns(Symbol) }
  protected def selected_link
    :business_member_privilege_rulesets
  end

  sig { override.returns(T::Array[String]) }
  protected def supported_targets
    %w[member_privilege]
  end

  sig { override.returns(String) }
  protected def layout
    "react_business"
  end

  private

  def enterprise_rulesets_enabled
    render_404 unless current_source.enterprise_rulesets_enabled?
  end

end
