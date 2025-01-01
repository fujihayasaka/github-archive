# typed: true
# frozen_string_literal: true

class Site::LabController < Site::About::BaseController
  stylesheet_bundle "site-lab"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  before_action :employee_only

  javascript_bundle "marketing-lab"

  def index
    render "site/lab/index"
  end

  def layout # rubocop:todo GitHub/UseRestfulActions
    render "site/lab/layout"
  end

  def typography # rubocop:todo GitHub/UseRestfulActions
    render "site/lab/typography"
  end

  def copilot # rubocop:todo GitHub/UseRestfulActions
    render "site/lab/copilot"
  end

  def editor # rubocop:todo GitHub/UseRestfulActions
    render "site/lab/editor"
  end
end
