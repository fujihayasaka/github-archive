# typed: true
# frozen_string_literal: true

class Stafftools::Users::Billing::CopilotPremiumUsageReportController < Stafftools::Users::BillingController
  include Copilot::Usage
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:create]

  sig { void }
  def create
    entity = if this_user.is_a?(Organization)
      Copilot::Organization.new(this_user)
    else
      Copilot::User.new(this_user)
    end

    premium_usage_csv_request(entity: entity, user_id: current_user&.id)
  end
end
