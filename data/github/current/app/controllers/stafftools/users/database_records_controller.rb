# typed: true
# frozen_string_literal: true

class Stafftools::Users::DatabaseRecordsController < StafftoolsController
  include Stafftools::Users::ControllerLayoutMethods

  before_action :ensure_user_exists

  layout :overview_layout

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  def show
    database_view = Stafftools::User::DatabaseView.new(user: this_user)
    render "stafftools/users/database_records/show", locals: { view: database_view }
  end
end
