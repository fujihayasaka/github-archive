# typed: true
# frozen_string_literal: true

class Stafftools::Users::SiteAdminsController < StafftoolsController
  include Stafftools::Users::ControllerMethods

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Configurations,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  ERR_COULD_NOT_PROMOTE_GH = "You are not able to promote that user; you can only promote current "\
    "employees and must specify a reason for the log."
  ERR_COULD_NOT_PROMOTE_GHE = "You have to specify a reason for the log."

  before_action :ensure_user_exists, only: [:create]

  layout "stafftools"

  def index
    index_view = Stafftools::User::IndexView.new(title: "Site admins")
    users = paginate(User, user_query("gh_role = 'staff'"))

    instrument("staff.view_site_admins")
    render "stafftools/users/index", locals: { view: index_view, users: users }
  end

  def create
    if this_user.grant_site_admin_access(params[:reason])
      flash[:notice] = "#{this_user.login} promoted to site admin"

      redirect_to stafftools_user_administrative_tasks_path(this_user)
    else
      flash[:error] = if GitHub.enterprise?
        ERR_COULD_NOT_PROMOTE_GHE
      else
        ERR_COULD_NOT_PROMOTE_GH
      end

      redirect_to stafftools_user_administrative_tasks_path(this_user)
    end
  end
end
