# typed: true
# frozen_string_literal: true

class Stafftools::SuspendedUsersController < StafftoolsController
  include Stafftools::Users::ControllerMethods

  before_action :enterprise_required

  layout "stafftools"

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:index]

  def index
    index_view = Stafftools::User::IndexView.new(title: "Suspended users")
    users = paginate(User, user_query("suspended_at IS NOT NULL"))
    render "stafftools/users/index", locals: { view: index_view, users: users }
  end
end
