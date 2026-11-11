# typed: true
# frozen_string_literal: true

class Stafftools::GistMaintenanceController < StafftoolsController

  GISTS_PER_PAGE = 20

  def index
    show_status = params[:maintenance_status] || "failed"
    render "stafftools/gist_maintenance/index", locals: {
      status_names: Gist::MAINTENANCE_STATUSES,
      show_status: show_status,
      gists: Gist
        .where(maintenance_status: show_status)
        .order("last_maintenance_attempted_at ASC")
        .paginate(page: current_page, per_page: GISTS_PER_PAGE)
    }
  end

  def mark_as_broken # rubocop:todo GitHub/UseRestfulActions
    this_gist.mark_as_broken
    flash[:warn] = "This gist has been marked as broken. No further maintenance jobs will be run for it."
    redirect_to :back
  end

  def schedule_maintenance # rubocop:todo GitHub/UseRestfulActions
    # If the gist has no files on disk, we can't decide the maintenance queue name anyway,
    # so try to restore first if this is the case
    this_gist.restore_to_disk unless this_gist.exists_on_disk?

    queue = this_gist.maintenance_queue_name
    if queue.ok?
      this_gist.update_status :scheduled, last_maintenance_attempted_at: Time.now
      GistMaintenanceJob.set(queue: queue.value!).perform_later(this_gist.id)
      flash[:notice] = "Gist maintenance job enqueued"
    else
      flash[:notice] = "Could not schedule maintenance: #{queue.error}"
    end
    redirect_to :back
  end

  private

  def this_gist
    Gist.find(params[:id])
  end

end
