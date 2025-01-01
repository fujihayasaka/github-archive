# typed: true
# frozen_string_literal: true

class Site::SponsorsController < Site::BaseController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories

  before_action :enable_fullstory
  before_action :add_fullstory_csp_exceptions

  def index
    Site::LandingPagesController.dispatch(:show, request, response)
  end
end
