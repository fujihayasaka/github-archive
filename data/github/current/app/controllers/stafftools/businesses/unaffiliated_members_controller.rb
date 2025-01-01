# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::UnaffiliatedMembersController < Stafftools::Businesses::BusinessBaseController
  skip_before_action :dotcom_required, only: %i(index)
  before_action :check_for_owners, only: %i(index)

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
    only: %i(index)

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    render "stafftools/businesses/members", locals: {
      members: this_business
        .filtered_members(
          current_user,
          query: params[:query],
          role: "unaffiliated",
          ignore_org_membership_visibility: true,
          business_user_accounts_query: true,
          include_unaffiliated: true
        )
        .paginate(page: current_page, per_page: DEFAULT_PAGE_SIZE),
      members_title: "Unaffiliated members",
      members_url: stafftools_enterprise_unaffiliated_members_path(this_business)
    }
  end
end
