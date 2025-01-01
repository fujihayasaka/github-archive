# typed: true
# frozen_string_literal: true

class Customers::Billing::RepoUsageController < Customers::BillingController
  include Billing::Platform::Api::Utils
  include Billing::RepoUsageDependency

  depends_on_clusters ApplicationRecord::Collab,
                      ApplicationRecord::Configurations,
                      ApplicationRecord::IamAbilities,
                      ApplicationRecord::Mysql1,
                      ApplicationRecord::Repositories,
                      only: [:show]

  def show
    render_repo_usage_data(this_entity: this_entity, is_stafftools_route: false)
  end
end
