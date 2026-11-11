# typed: true
# frozen_string_literal: true

class Stafftools::GistCommentsController < StafftoolsController # rubocop:todo GitHub/ControllersShouldHaveTests
  before_action :ensure_user_exists

  def destroy
    comment = this_user.gist_comments.find_by(id: params[:comment_id])
    comment.destroy
    head 200
  end

end
