# typed: true
# frozen_string_literal: true

class Orgs::OauthApplicationTransfersController < Orgs::Controller

  include OauthApplicationTransfersControllerMethods

  before_action :organization_admin_required, except: [:destroy]

  javascript_bundle :settings
  stylesheet_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:show]

  private

  def current_context
    this_organization
  end
end
