# typed: true
# frozen_string_literal: true

class Stafftools::Users::SparksController < StafftoolsController
  include Stafftools::Users::ControllerLayoutMethods

  depends_on_clusters(
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:index]
  )

  before_action :ensure_user_exists

  layout "layouts/stafftools/user/content"

  def index
    sparks = Spark::Workbench.where(user: this_user).to_a
    render("stafftools/users/sparks/index", locals: { sparks: sparks, user: this_user })
  end

  def destroy
    spark = Spark::Workbench.for_uuid_string(this_user.id, params[:id])

    unless spark
      flash[:error] = "The Spark workbench could not be found."
      return redirect_to stafftools_user_sparks_path(this_user)
    end

    if spark.destroy
      flash[:notice] = "The Spark workbench has been deleted."
    else
      flash[:error] = "Error deleting the Spark workbench."
    end

    redirect_to stafftools_user_sparks_path(this_user)
  end
end
