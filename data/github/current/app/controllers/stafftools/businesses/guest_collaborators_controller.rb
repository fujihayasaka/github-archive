# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::GuestCollaboratorsController < Stafftools::Businesses::BusinessBaseController
  before_action :enterprise_managed_business_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    render "stafftools/businesses/guest_collaborators/index", locals: {
      guest_collaborators: this_business
        .filtered_members(
          current_user,
          ignore_org_membership_visibility: true,
          query: params[:query],
          role: "guest_collaborator"
        )
        .paginate(page: current_page, per_page: DEFAULT_PAGE_SIZE),
    }
  end
end
