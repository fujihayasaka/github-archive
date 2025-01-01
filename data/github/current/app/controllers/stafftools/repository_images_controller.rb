# typed: true
# frozen_string_literal: true

class Stafftools::RepositoryImagesController < StafftoolsController
  before_action :ensure_user_exists

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Ballast,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql5,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    render "stafftools/repository_images/index", layout: "layouts/stafftools/repository/overview"
  end

  def destroy
    image = RepositoryImage.find(params[:id])
    image.destroyer = current_user

    if image.destroy
      flash[:notice] = "Successfully deleted image"
    else
      flash[:error] = "Error deleting image: " + image.errors.full_messages.to_sentence
    end

    redirect_to stafftools_repository_images_path(params[:user_id], params[:repository_id])
  end
end
