# typed: true
# frozen_string_literal: true

class Businesses::CodeRulesBypassRequestsController < Businesses::BusinessController
  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :business_full_plan_required

  include ApplicationController::VerifiedFetchDependency
  include BypassRequestsControllerMethods

  allow_verified_fetch only: FETCH_ENDPOINTS

  sig { override.returns(Business) }
  protected def current_source
    this_business
  end

  sig { override.returns(Symbol) }
  protected def selected_link
    :business_code_rule_bypass_requests
  end

  sig { override.returns(String) }
  protected def layout
    "react_business"
  end

  sig { override.returns(String) }
  protected def title
    "Settings · Bypass Requests · #{this_business.name}"
  end

  sig { override.void }
  def index
    render_404 unless current_source.feature_enabled?(:push_ruleset_delegated_bypass)

    super
  end
end
