# typed: true
# frozen_string_literal: true

class Orgs::LicensingHeadroomController < Orgs::Controller
  before_action :login_required
  before_action :organization_admin_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  def show
    render(Organizations::LicensingHeadroomComponent.new(
      remaining_units: this_organization.total_available_seats,
      unit_of_measure: helpers.seat_or_license(this_organization),
      more_units_link_markup: helpers.more_seats_link_for_organization(this_organization, self_serve_return_to: org_people_path(this_organization)),
      more_information_markup: helpers.render_seats_more_info(this_organization)
    ), layout: false)
  end
end
