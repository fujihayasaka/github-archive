# typed: true
# frozen_string_literal: true

class Orgs::CopilotSettings::EnableController < Orgs::Controller
  extend T::Sig

  before_action :dotcom_required
  before_action :org_admins_only

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

  def index
    if copilot_organization.is_business_in_trial_period?
      return render "settings/organization/copilot/enable/enterprise_trial"
    end

    unless copilot_organization.has_copilot_for_business? || copilot_organization.is_available_for_copilot_signup?
      return render_404
    end

    render "settings/organization/copilot/enable/index"
  end

  private

  sig { returns Copilot::Organization }
  memoize def copilot_organization
    T.must_because(current_copilot_organization) { "#org_admins_only ensures non-nil" }
  end
end
