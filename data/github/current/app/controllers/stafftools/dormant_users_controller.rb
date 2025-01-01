# typed: true
# frozen_string_literal: true

class Stafftools::DormantUsersController < StafftoolsController
  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:index]

  TIMEOUT_SECONDS = 21

  before_action :enterprise_required

  layout "stafftools"

  def index
    index_view = Stafftools::User::IndexView.new(title: "Dormant users")
    users = User.dormant_users(timeout_seconds: TIMEOUT_SECONDS).paginate(page: current_page)
    render "stafftools/dormant_users/index", locals: { view: index_view, users: users }
  end
end
