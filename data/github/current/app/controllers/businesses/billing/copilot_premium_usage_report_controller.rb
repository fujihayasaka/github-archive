# typed: strict
# frozen_string_literal: true

class Businesses::Billing::CopilotPremiumUsageReportController < Businesses::BillingsController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    only: [:show]

  before_action :login_required

  sig { void }
  def show
    csv = Copilot::Business.new(this_business).premium_usage_csv

    send_data csv, filename: "#{this_business.slug}-copilot-premium-usage-report.csv"
  end
end
