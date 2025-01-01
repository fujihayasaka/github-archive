# typed: strict
# frozen_string_literal: true

class Orgs::CopilotSettings::MemberSearchController < Orgs::Controller
  include ApplicationHelper
  include AvatarHelper
  include ApplicationController::JsonDependency

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:index]

  before_action :dotcom_required
  before_action :org_admins_only
  before_action :check_not_legacy_plan
  before_action :check_copilot_available

  sig { void }
  def index
    payload = Copilot::Organizations::SeatManagement::MemberSearchPayload.new(organization: current_organization,
                                                                              params: params,
                                                                              current_user: current_user).call
    render json: payload
  end

  private

  sig { returns(Copilot::Organization) }
  memoize def copilot_org
    T.must_because(current_copilot_organization) { "#org_admins_only ensures non-nil" }
  end

  sig { void }
  def check_not_legacy_plan
    render_404 if current_organization.plan.legacy?
  end

  sig { void }
  def check_copilot_available
    render_404 unless copilot_org.has_copilot_for_business? || (copilot_org.business_trial && T.must(copilot_org.business_trial).has_trial?)
  end
end
