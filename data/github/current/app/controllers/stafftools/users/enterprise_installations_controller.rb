# typed: true
# frozen_string_literal: true

class Stafftools::Users::EnterpriseInstallationsController < StafftoolsController
  include Stafftools::Users::ControllerLayoutMethods

  before_action :ensure_user_exists
  before_action :ensure_org_not_user
  before_action :dotcom_required

  layout :security_layout

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    installations = this_user \
      .enterprise_installations
      .order("created_at desc")
      .paginate(page: params[:page])

    render \
      "stafftools/organizations/enterprise_installations/index",
      locals: { installations: installations }
  end
end
