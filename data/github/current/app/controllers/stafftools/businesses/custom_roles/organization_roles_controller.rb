# typed: strict
# frozen_string_literal: true

class Stafftools::Businesses::CustomRoles::OrganizationRolesController < Stafftools::Businesses::BusinessBaseController
  skip_before_action :dotcom_required, only: %i(index)

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  sig { void }
  def index
    render "stafftools/businesses/custom_roles/organization_roles/index"
  end
end
