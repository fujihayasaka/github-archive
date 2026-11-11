# typed: true
# frozen_string_literal: true

class Stafftools::Repositories::MergeQueueEntriesController < StafftoolsController
  include MergeQueues::SharedControllerMethods

  before_action :ensure_repo_exists

  rescue_from Exception, with: :handle_exception

  def destroy
    entry = merge_queue&.entries&.find_by(id: params[:merge_queue_entry_id])
    return render_404 unless entry.present?

    MergeQueues.remove!(queue: merge_queue, entry:, actor: current_user)
    flash[:notice] = "PR ##{entry.pull_request.number} removed from queue"
    redirect_to_merge_queue
  end

  private

  def redirect_to_merge_queue
    redirect_to stafftools_merge_queue_path(current_repository.owner_display_login, current_repository, merge_queue.branch)
  end

  def handle_exception(e)
    return render_404 unless merge_queue.present?
    flash[:error] = e.message
    redirect_to_merge_queue
  end
end
