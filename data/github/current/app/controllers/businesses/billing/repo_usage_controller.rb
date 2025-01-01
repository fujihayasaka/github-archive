# typed: true
# frozen_string_literal: true

class Businesses::Billing::RepoUsageController < Businesses::BillingsController
  include Billing::Platform::Api::Utils
  include ApplicationController::VerifiedFetchDependency
  include Businesses::Billing::Concerns::RepoUsage

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    only: [:show]

  def show
    render_repo_usage_data(this_entity: this_business, is_stafftools_route: false)
  end
end
