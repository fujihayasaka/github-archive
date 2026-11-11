# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::UnaffiliatedMembersBulkRemovalController < Stafftools::Businesses::BusinessBaseController
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Stafftools::Businesses::UnaffiliatedMembersBulkRemovalController#destroy"
  ].freeze

  skip_before_action :dotcom_required, only: %i(destroy)
  before_action :check_for_owners, only: %i(destroy)

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Accounts,
    only: %i(destroy)

  def destroy
    synchronizer = BusinessUserAccount::SynchronizeAccounts.new(business: this_business, actor: current_user)
    orchestration = synchronizer.remove_unaffiliated_accounts

    if orchestration.skipped?
      flash[:notice] = "No unaffiliated users to remove."
    else
      flash[:notice] = "Unaffiliated users removal started. This may take a few minutes."
    end

    redirect_to stafftools_enterprise_people_path(this_business)
  end
end
