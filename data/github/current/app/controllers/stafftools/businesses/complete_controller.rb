# typed: strict
# frozen_string_literal: true

class Stafftools::Businesses::CompleteController < Stafftools::Businesses::BusinessBaseController
  ADD_OWNERS_PAGE_SIZE = 10

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    only: %i(show)

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  sig { void }
  def show
    render "stafftools/businesses/complete", locals: {
      owners: this_business.owners.paginate(page: current_page, per_page: ADD_OWNERS_PAGE_SIZE),
      pending_owner_invitations:
        this_business.pending_admin_invitations(role: [:owner])
          .paginate(page: current_page, per_page: ADD_OWNERS_PAGE_SIZE),
    }
  end
end
