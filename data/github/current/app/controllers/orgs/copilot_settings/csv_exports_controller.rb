# typed: strict
# frozen_string_literal: true
class Orgs::CopilotSettings::CsvExportsController < Orgs::Controller
  extend T::Sig

  before_action :dotcom_required
  before_action :org_admins_only
  before_action :check_exports_available

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

  sig { void }
  def index
    render "orgs/copilot_settings/csv_exports/index", locals: { copilot_organization: copilot_organization }
  end

  sig { void }
  def create
    GitHub.logger.info("Generating specialty CSV", "gh.org.id" => current_organization.id, "gh.user.id" => current_user.id)
    send_data copilot_organization.to_csv, filename: "#{current_organization.display_login.parameterize}-seat-usage-#{Time.current.to_i}.csv"
  end

  private

  sig { void }
  def check_exports_available
    render_404 unless copilot_organization.show_csv_exports?
  end

  sig { returns(Copilot::Organization) }
  memoize def copilot_organization
    T.must_because(current_copilot_organization) { "#org_admins_only ensures non-nil" }
  end
end
