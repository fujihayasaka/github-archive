# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::PendingCollaboratorsController < Stafftools::Businesses::BusinessBaseController
  before_action :check_for_owners, only: %i(index)

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    only: %i(index)

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  def index
    render "stafftools/businesses/pending_collaborators", locals: {
      pending_collaborator_invitations: this_business
        .pending_collaborator_invitations(query: params[:query])
        .paginate(page: current_page, per_page: DEFAULT_PAGE_SIZE),
    }
  end
end
