# typed: true
# frozen_string_literal: true

class Repos::AdvisoryCommentsActionsMenuController < Repos::AdvisoryBaseController
  before_action :login_required
  before_action :advisory
  before_action :authorize_advisory_writable

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  def show
    return render_404 unless request.xhr?

    current_comment = advisory.comments.find_by(id: params[:comment_id])
    return render_404 unless current_comment

    current_comment.preload_viewer_attributes(current_user, current_repository)

    render partial: "comments/comment_header_details_menu", locals: {
      comment: current_comment,
      viewer: current_user,
      repository: current_repository,
      form_path: (
        update_repository_advisory_comment_path(
          id: advisory.ghsa_id,
          comment_id: current_comment.id
        )
      ),
      # TODO @ktravers: update to `parent_path` or something that's not specific to issues
      issue_path: (
        repository_advisory_path(
          current_repository.owner_display_login,
          current_repository.name,
          advisory.ghsa_id
        )
      ),
      href: params[:href]
    }
  end
end
