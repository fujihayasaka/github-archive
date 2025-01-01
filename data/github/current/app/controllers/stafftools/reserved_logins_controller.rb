# typed: false
# frozen_string_literal: true

class Stafftools::ReservedLoginsController < StafftoolsController

  before_action :dotcom_required, only: [:create, :destroy]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:search]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :search],
    optional: true

  def index
    return redirect_to stafftools_reserved_login_path(login: params[:login]) if params[:login]

    reserved_logins = ReservedLogin.
      staff_reserved.
      order("login ASC").
      paginate(page: current_page, per_page: 30)
    render "stafftools/reserved_logins/index", locals: { reserved_logins: reserved_logins, restricted_login_keywords: ReservedLogin.restricted_login_keywords }
  end

  def create
    Audit.context.push(reason: params[:reason])
    ReservedLogin.reserve!(params[:login])
    flash[:notice] = "Login #{params[:login]} reserved."
  rescue ActiveRecord::RecordInvalid => error
    flash[:error] = error.record.errors.full_messages.join(", ")
  ensure
    redirect_to :back
  end

  def destroy
    login = ReservedLogin.find_by_login(params[:login])

    if login.destroy
      flash[:notice] = "Login #{params[:login]} unreserved."
      redirect_to :back
    else
      flash[:error] = login.errors.messages.values.join(", ")
      redirect_to :back
    end
  end

  def search # rubocop:todo GitHub/UseRestfulActions
    render "stafftools/reserved_logins/search", locals: {
        reserved_login: ReservedLogin.find_by_login(params[:login]),
    }
  end
end
