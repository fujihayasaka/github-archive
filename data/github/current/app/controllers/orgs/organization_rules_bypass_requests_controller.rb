# typed: true
# frozen_string_literal: true

class Orgs::OrganizationRulesBypassRequestsController < Orgs::Controller
  before_action :organization_admin_required

  include ApplicationController::VerifiedFetchDependency
  include BypassRequestsControllerMethods

  allow_verified_fetch only: FETCH_ENDPOINTS

  sig { override.returns(Organization) }
  protected def current_source
    current_organization
  end

  sig { override.returns(Symbol) }
  protected def selected_link
    :org_rules_bypass_requests
  end

  sig { override.returns(String) }
  protected def layout
    "layouts/settings/rules"
  end

  sig { override.returns(String) }
  protected def title
    "Settings · Bypass Requests · #{current_organization.name_with_display_owner}"
  end
end
