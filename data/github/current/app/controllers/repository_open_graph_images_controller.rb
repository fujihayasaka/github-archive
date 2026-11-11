# typed: true
# frozen_string_literal: true

class RepositoryOpenGraphImagesController < AbstractRepositoryController
  # rubocop:disable GitHub/DoNotSkipCapBeforeAction
  skip_before_action :perform_conditional_access_checks, only: [:template]
  # rubocop:enable GitHub/DoNotSkipCapBeforeAction
  before_action :login_required
  before_action :set_open_graph_image_permission_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:template]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:template],
    optional: true

  def template # rubocop:todo GitHub/UseRestfulActions
    path = Rails.root.join("public", "static", "images", "repository-og-image-template.png")
    send_file path, type: "image/png", filename: "repository-open-graph-template.png"
  end

  def destroy
    image = current_repository.repository_images.find(params[:id])
    image.destroyer = current_user

    unless image.destroy
      flash[:error] = "Could not delete repository image: #{image.errors.full_messages.to_sentence}"
    end

    redirect_to edit_repository_path(params[:user_id], params[:repository])
  end

  def set_open_graph_image_permission_required # rubocop:todo GitHub/UseRestfulActions
    render_404 unless current_repository.async_can_set_social_preview?(current_user).sync
  end
end
