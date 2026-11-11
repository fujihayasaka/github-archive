# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::PendingBillingManagersController < Stafftools::Businesses::BusinessBaseController
  before_action :check_for_owners, only: %i(index)

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: %i(index)

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  def index
    invitations = this_business.pending_admin_invitations(query: params[:query], role: [:billing_manager])
      .paginate(page: current_page, per_page: DEFAULT_PAGE_SIZE)
    render "stafftools/businesses/pending_billing_managers",
      locals: { pending_billing_manager_invitations: invitations }
  end
end
