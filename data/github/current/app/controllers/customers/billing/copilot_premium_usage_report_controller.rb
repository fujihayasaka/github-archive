# typed: strict
# frozen_string_literal: true

class Customers::Billing::CopilotPremiumUsageReportController < Customers::BillingController
  before_action :login_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    only: [:show]

  sig { void }
  def show
    csv = Copilot::User.new(this_user).premium_usage_csv

    send_data csv, filename: "#{this_user.display_login}-copilot-premium-usage-report.csv"
  end
end
