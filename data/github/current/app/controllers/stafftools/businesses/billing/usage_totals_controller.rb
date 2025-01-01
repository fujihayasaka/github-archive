# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::Billing::UsageTotalsController < Stafftools::Businesses::BillingController
  include ApplicationController::VerifiedFetchDependency
  include Billing::Platform::Api::Utils
  include Billing::UsageTotalsDependency

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
  only: [:show]

  before_action :ensure_vnext_enabled
  allow_verified_fetch only: [:show]

  def show
    render_usage_totals_data(this_entity: this_business, is_stafftools_route: true)
  end
end
