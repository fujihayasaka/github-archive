# typed: false
# frozen_string_literal: true

class Stafftools::GistsController < StafftoolsController

  before_action :dotcom_required,
    only: [:dmca_takedown, :dmca_restore, :country_block, :remove_country_block]
  before_action :ensure_user_exists, except: [:show, :destroy, :restore, :purge]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:deleted]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Spokes,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:show, :index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:deleted, :index, :show], optional: true

  def index
    gists = this_user.gists.are_public.order("gists.delete_flag, gists.created_at DESC").paginate page: current_page

    view = create_view_model(
      Stafftools::User::GistsView,
      gists: gists,
      user: this_user,
    )
    render "stafftools/gists/index", layout: "layouts/stafftools/user/content", locals: { view: view }
  end

  def deleted # rubocop:todo GitHub/UseRestfulActions
    gists_deleted = Gist.deleted.where(user_id: this_user.id).order("updated_at DESC")
    view = create_view_model(
      Stafftools::User::GistsView,
      gists: gists_deleted.paginate(page: current_page),
      user: this_user,
      gist_type: "deleted",
    )
    render "stafftools/gists/deleted", layout: "layouts/stafftools/user/content", locals: { view: view }
  end

  def show
    layout = "layouts/stafftools/user/content"
    layout = "layouts/stafftools/anonymous_gist" if this_gist.anonymous?
    view = create_view_model(
      Stafftools::User::GistView,
      gist: this_gist,
    )
    render "stafftools/gists/show", layout: layout, locals: { view: view }
  end

  def restore # rubocop:todo GitHub/UseRestfulActions
    deleted_gist = this_gist

    if deleted_gist.is_a?(Gist) && deleted_gist.deleted?
      restored_gist = Gist.restore(deleted_gist.id)
      instrument "staff.restore_gist", restored_gist.event_payload

      redirect_to stafftools_user_gist_path(restored_gist.user_param, restored_gist)
    else
      redirect_to :back
    end
  end

  def dmca_takedown # rubocop:todo GitHub/UseRestfulActions
    url = params["takedown_url"]

    if this_gist.access.dmca_takedown(current_user, url)
      flash[:notice] = "Takedown processed"
    else
      flash[:error] = this_gist.errors[:base].to_sentence
    end

    redirect_to :back
  end

  def dmca_restore # rubocop:todo GitHub/UseRestfulActions
    if !this_gist.access.dmca?
      flash[:notice] = "No takedown notice on file"
    elsif this_gist.access.enable(current_user)
      flash[:notice] = "Takedown removed"
    else
      flash[:error] = "Failed to remove DMCA takedown"
    end

    redirect_to :back
  end

  def country_block # rubocop:todo GitHub/UseRestfulActions
    country = params["country_block"]
    url = params["country_block_url"]
    reason = params["country_block_reason"]

    if this_gist.access.country_block(current_user, country, url, reason)
      flash[:notice] = "Country block processed. This may take up to ten minutes to take effect."
    else
      flash[:error] = this_gist.errors[:base].to_sentence
    end

    redirect_to :back
  end

  def remove_country_block # rubocop:todo GitHub/UseRestfulActions
    country = params["country_block"]

    if !this_gist.access.country_block_setup?(country)
      flash[:notice] = "Given country block not registered"
    elsif this_gist.access.remove_country_block(current_user, country)
      flash[:notice] = "Country block removed. This may take up to ten minutes to take effect."
    else
      flash[:error] = "Failed to remove country block"
    end

    redirect_to :back
  end

  def destroy
    if params[:tos_reason].blank?
      flash[:error] = "Must include DSA violating reason when deleting a Gist"
      redirect_to :back and return
    end

    if params[:content_formats].blank?
      flash[:error] = "Must specify at least one violating content format when deleting a Gist"
      redirect_to :back and return
    end

    this_gist.remove

    instrument "staff.delete_gist", this_gist.event_payload
    GlobalInstrumenter.instrument "staff.delete_gist", {
      actor: current_user,
      gist: this_gist,
      tos_reason: params[:tos_reason],
      content_formats: params[:content_formats],
      source: params[:source]
    }

    flash[:notice] = "Gist deleted"

    redirect_to stafftools_path
  end

  def purge # rubocop:todo GitHub/UseRestfulActions
    this_gist.purge

    flash[:notice] = "Gist purged"

    redirect_to stafftools_path
  end

  def schedule_backup # rubocop:todo GitHub/UseRestfulActions
    this_gist.async_backup
    flash[:notice] = "Gist backup job scheduled"
    redirect_to :back
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

  def block_archive_download # rubocop:todo GitHub/UseRestfulActions
    this_gist.block_archive_resource(actor: this_user)
    redirect_to :back
  end

  def unblock_archive_download # rubocop:todo GitHub/UseRestfulActions
    this_gist.unblock_archive_resource(actor: this_user)
    redirect_to :back
  end

  private

  memoize def this_gist
    @gist ||= if this_user
      this_user.gists.find_by_repo_name! params[:id]
    else
      Gist.anonymous.find_by_repo_name! params[:id]
    end
  end
end
