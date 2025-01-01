# typed: strict
# frozen_string_literal: true

class OrganizationOnboarding::ApplicationController < ::ApplicationController
  include OrganizationsHelper

  before_action :login_required
  before_action :require_organization_admin
  before_action :dotcom_required

  sig { returns(Organization) }
  private def target_for_conditional_access
    this_organization
  end

  private

  sig { void }
  def require_organization_admin
    render_404 unless this_organization.adminable_by?(current_user)
  end

  sig { returns(Organization) }
  memoize def this_organization
    Organization.find_by!(login: params[:org])
  end
end
