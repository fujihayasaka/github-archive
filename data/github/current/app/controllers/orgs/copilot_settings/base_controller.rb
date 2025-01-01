# typed: true
# frozen_string_literal: true

class Orgs::CopilotSettings::BaseController < Orgs::Controller
  include ApplicationHelper

  before_action :dotcom_required
  before_action :org_admins_only

  private

  sig { returns(Copilot::Organization) }
  memoize def copilot_organization
    T.must_because(current_copilot_organization) { "#org_admins_only ensures non-nil" }
  end

  sig { void }
  def check_copilot_available
    render_404 unless copilot_organization.has_copilot_for_business? || (copilot_organization.business_trial && T.must(copilot_organization.business_trial).has_trial?)
  end
end
