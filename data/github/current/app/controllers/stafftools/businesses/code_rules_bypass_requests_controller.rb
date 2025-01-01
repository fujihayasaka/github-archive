# typed: strict
# frozen_string_literal: true

class Stafftools::Businesses::CodeRulesBypassRequestsController < Stafftools::Businesses::BusinessBaseController
  include ApplicationController::VerifiedFetchDependency
  include BypassRequestsControllerMethods

  depends_on_clusters ApplicationRecord::Ballast

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
    "layouts/stafftools/business"
  end

  sig { override.returns(String) }
  protected def title
    "Settings · Bypass Requests · #{this_business.name}"
  end

  sig { override.returns(T::Boolean) }
  protected def stafftools?
    true
  end
end
