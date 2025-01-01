# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::DeletedOrganizationsController < Stafftools::Businesses::BusinessBaseController
  skip_before_action :dotcom_required, only: %w(index)
  before_action :check_for_owners, only: %w(index)

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::IssuesPullRequests,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    render "stafftools/businesses/deleted_organizations", locals: {
      business: this_business,
      organizations: this_business
        .filtered_organizations(query: params[:query], only_deleted: true)
        .paginate(page: current_page, per_page: DEFAULT_PAGE_SIZE),
    }
  end

end
