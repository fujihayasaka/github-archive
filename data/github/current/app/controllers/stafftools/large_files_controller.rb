# typed: true
# frozen_string_literal: true

class Stafftools::LargeFilesController < StafftoolsController
  before_action :ensure_user_exists,
                only: [:enable_user_preview, :disable_user_preview, :rebuild_status]
  before_action :ensure_repo_exists,
                except: [:enable_user_preview, :disable_user_preview, :rebuild_status]

  layout "layouts/stafftools/repository/storage"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    render "stafftools/large_files/index"
  end

  def archive # rubocop:todo GitHub/UseRestfulActions
    file = Media::Blob.fetch_by_id(current_repository, params[:id].to_i)
    if file.nil? || file.archived?
      flash[:error] = "Large file does not exist."
    else
      if file.archive
        flash[:notice] = "File was archived successfully."
      else
        flash[:notice] = "Incomplete file record was deleted."
      end
    end

    redirect_to :back
  end

  def unarchive # rubocop:todo GitHub/UseRestfulActions
    file = Media::Blob.fetch_by_id(current_repository, params[:id].to_i)
    if file && file.archived?
      if file.unarchive
        flash[:notice] = "File has been restored."
      else
        flash[:error] = "File is not restorable."
      end
    else
      flash[:error] = "Large file does not exist, or is not deleted."
    end

    redirect_to :back
  end

  def purge_objects # rubocop:todo GitHub/UseRestfulActions
    UpdateNetworkMediaBlobsJob.perform_later({ "action" => :archive, "network_id" => current_repository.network_id })

    flash[:notice] = "Queued all LFS objects in #{current_repository.nwo} for archival"
    redirect_to :back
  end

  def restore_objects # rubocop:todo GitHub/UseRestfulActions
    UpdateNetworkMediaBlobsJob.perform_later({ "action" => :unarchive, "network_id" => current_repository.network_id })

    flash[:notice] = "Queued all LFS objects in #{current_repository.nwo} to be restored"
    redirect_to :back
  end

  def enable_repo_preview # rubocop:todo GitHub/UseRestfulActions
    if !GitHub.git_lfs_config_enabled?
      flash[:error] = "Git LFS support not enabled because Git LFS is globally disabled."
    elsif !current_repository.network_root? && current_repository.root && !current_repository.root.git_lfs_enabled?
      flash[:error] = "Git LFS support not enabled because Git LFS is disabled for the root repository in the network."
    elsif !current_repository.owner.git_lfs_enabled?
      flash[:error] = "Git LFS support not enabled because Git LFS is disabled for #{current_repository.owner.display_login}."
    else
      current_repository.enable_git_lfs(current_user)
      flash[:notice] = "Git LFS support enabled."
    end
    redirect_to :back
  end

  def disable_repo_preview # rubocop:todo GitHub/UseRestfulActions
    current_repository.disable_git_lfs(current_user)
    flash[:notice] = "Git LFS support disabled."
    redirect_to :back
  end

  def enable_user_preview # rubocop:todo GitHub/UseRestfulActions
    if GitHub.git_lfs_config_enabled?
      this_user.enable_git_lfs(current_user)
      flash[:notice] = "Git LFS support enabled."
    else
      flash[:error] = "Git LFS support not enabled because Git LFS is globally disabled."
    end
    redirect_to :back
  end

  def disable_user_preview # rubocop:todo GitHub/UseRestfulActions
    this_user.disable_git_lfs(current_user)
    flash[:notice] = "Git LFS support disabled."
    redirect_to :back
  end

  def rebuild_status # rubocop:todo GitHub/UseRestfulActions
    this_user.rebuild_asset_status(notify: false, manual: true)
    flash[:notice] = "Rebuilding storage usage."
    redirect_to :back
  end

  def change_timeout # rubocop:todo GitHub/UseRestfulActions
    current_repository.set_lfs_integrity_check_timeout(params[:timeout], current_user)
    flash[:notice] = "LFS integrity check timeout set"
    redirect_to :back
  end
end
