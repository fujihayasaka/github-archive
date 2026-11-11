# typed: strict
# frozen_string_literal: true

class Customers::Billing::CopilotPremiumUsageReportController < Customers::BillingController
  include Copilot::Usage
  include ApplicationController::VerifiedFetchDependency

  before_action :login_required
  allow_verified_fetch only: [:create]

  sig { void }
  def create
    premium_usage_csv_request(entity: Copilot::User.new(this_user), user_id: current_user.id)
  end
end
