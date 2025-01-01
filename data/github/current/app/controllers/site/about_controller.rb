# typed: true
# frozen_string_literal: true

class Site::AboutController < Site::About::BaseController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    only: [:index]

  before_action :enable_fullstory
  before_action :add_fullstory_csp_exceptions

  def index
    render "site/about/index"
  end
end
