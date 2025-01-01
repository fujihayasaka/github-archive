# typed: true
# frozen_string_literal: true

class Orgs::ConsumedLicensesController < Orgs::Controller
  skip_before_action :cap_pagination, only: [:show]
  before_action :ensure_billing_enabled
  before_action :this_organization_required
  before_action :org_billing_management_only
  before_action :ensure_organization_on_per_seat_plan

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    only: [:show]

  def show
    render(
      "orgs/consumed_licenses/show",
      locals: {
        view: Orgs::ConsumedLicensesView.new(organization: this_organization, page: params[:page]),
      },
    )
  end

  private

  def ensure_organization_on_per_seat_plan
    render_404 unless this_organization.plan.per_seat?
  end
end
