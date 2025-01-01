# typed: strict
# frozen_string_literal: true

class Orgs::CopilotPremiumUsageReportController < Orgs::Controller
  before_action :login_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    only: [:show]

  sig { void }
  def show
    csv = Copilot::Organization.new(this_organization).premium_usage_csv

    send_data csv, filename: "#{this_organization.display_login}-copilot-premium-usage-report.csv"
  end
end
