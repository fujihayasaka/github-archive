# typed: true
# frozen_string_literal: true

class Orgs::MemberPrivilegeRulesetsController < Orgs::Controller
  extend T::Sig

  include RulesetViewControllerMethods
  include RulesetEditControllerMethods
  include ApplicationController::VerifiedFetchDependency

  before_action :org_ref_rules_manager_only
  before_action :ensure_trade_restrictions_allows_org_settings_access

  before_action :ensure_feature_enabled

  allow_verified_fetch only: [:ruleset_update, :ruleset_destroy, :ruleset_validate_value]

  sig { override.returns(RuleEngine::Types::RuleSource) }
  protected def current_source
    current_organization
  end

  sig { override.returns(String) }
  protected def index_path
    settings_org_member_privilege_rules_path
  end

  sig { override.returns(Symbol) }
  protected def selected_link
    :member_privilege_rulesets
  end

  sig { override.returns(T::Array[String]) }
  protected def supported_targets
    %w[member_privilege]
  end

  private

  def ensure_feature_enabled
    render_404 if !current_organization.member_privilege_rulesets_enabled?
  end

end
