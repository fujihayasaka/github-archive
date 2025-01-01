# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::Billing::RepoUsageController < Stafftools::Businesses::BillingController
  include Billing::Platform::Api::Utils
  include ApplicationController::VerifiedFetchDependency
  include Businesses::Billing::Concerns::RepoUsage

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:show]

  before_action :ensure_vnext_enabled
  allow_verified_fetch only: [:index]

  def show
    render_repo_usage_data(this_entity: this_business, is_stafftools_route: true)
  end
end
