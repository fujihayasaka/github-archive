# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::Billing::CopilotPremiumUsageReportController < Stafftools::Businesses::BillingController
  include Copilot::Usage
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:create]

  sig { void }
  def create
    premium_usage_csv_request(entity: Copilot::Business.new(this_business), user_id: current_user&.id)
  end
end
