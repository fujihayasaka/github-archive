# typed: true
# frozen_string_literal: true

class Stafftools::Orgs::SafeguardLimitsController < StafftoolsController
  include Stafftools::Users::ControllerLayoutMethods

  before_action :ensure_user_exists
  before_action :ensure_org_not_user

  layout :overview_layout

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    only: [:index]

  def index
    render "stafftools/organizations/safeguard_limits/index"
  end
end
