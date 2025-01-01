# typed: strict
# frozen_string_literal: true

class Stafftools::Businesses::CustomRoles::EnterpriseRolesController < Stafftools::Businesses::BusinessBaseController
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
    render "stafftools/businesses/custom_roles/enterprise_roles/index"
  end
end
