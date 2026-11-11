# typed: true
# frozen_string_literal: true

class Stafftools::Users::Repositories::RolesController < StafftoolsController
  include Stafftools::Users::ControllerLayoutMethods

  before_action :ensure_org_not_user
  before_action :ensure_user_exists

  layout :security_layout

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Iam,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    render "stafftools/organizations/repositories/roles/index", locals: { organization: this_user }
  end
end
