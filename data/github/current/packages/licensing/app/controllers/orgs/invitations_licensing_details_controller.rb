# typed: true
# frozen_string_literal: true

class Orgs::InvitationsLicensingDetailsController < Orgs::Controller
  before_action :login_required
  before_action :organization_admin_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  def show
    render "orgs/invitations_licensing_details/show",
      locals: {
        organization: this_organization,
        remaining_seats_or_licenses: this_organization.total_available_seats,
        enterprise_managed_user_enabled: !!this_organization&.enterprise_managed_user_enabled?,
      },
      layout: false
  end
end
