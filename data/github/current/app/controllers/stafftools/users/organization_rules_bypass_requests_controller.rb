# typed: strict
# frozen_string_literal: true

class Stafftools::Users::OrganizationRulesBypassRequestsController < StafftoolsController
  include ApplicationController::VerifiedFetchDependency
  include BypassRequestsControllerMethods

  depends_on_clusters ApplicationRecord::Ballast

  allow_verified_fetch only: FETCH_ENDPOINTS

  sig { override.returns(Organization) }
  protected def current_source
    this_user
  end

  sig { override.returns(Symbol) }
  protected def selected_link
    :org_rules_bypass_requests
  end

  sig { override.returns(String) }
  protected def layout
    "layouts/stafftools/organization/overview"
  end

  sig { override.returns(String) }
  protected def title
    "Settings · Bypass Requests · #{this_user.name_with_display_owner}"
  end

  sig { override.returns(T::Boolean) }
  protected def stafftools?
    true
  end
end
