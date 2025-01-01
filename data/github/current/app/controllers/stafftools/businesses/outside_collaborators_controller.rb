# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::OutsideCollaboratorsController < Stafftools::Businesses::BusinessBaseController
  skip_before_action :dotcom_required, only: %i(index)
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
    only: %i(index)

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    outside_collaborators = this_business
      .filtered_outside_collaborators(query: params[:query])
      .paginate(page: current_page, per_page: DEFAULT_PAGE_SIZE)
    private_outside_collaborator_ids = this_business
      .filtered_outside_collaborators(visibility: [:private]).ids

    render "stafftools/businesses/outside_collaborators", locals: {
      private_outside_collaborator_ids: private_outside_collaborator_ids,
      outside_collaborators: outside_collaborators,
    }
  end
end
