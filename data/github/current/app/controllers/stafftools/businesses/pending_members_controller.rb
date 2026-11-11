# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::PendingMembersController < Stafftools::Businesses::BusinessBaseController
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
    ApplicationRecord::Configurations,
    only: %i(index)

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  def index
    render "stafftools/businesses/pending_members", locals: {
      pending_member_invitations: this_business
        .pending_member_invitations(
          query: params[:query],
          order_by_field: "created_at",
          order_by_direction: "desc"
        )
        .paginate(page: current_page, per_page: DEFAULT_PAGE_SIZE),
    }
  end
end
