# typed: true
# frozen_string_literal: true

class Stafftools::UserAssetsController < StafftoolsController
  include GitHub::Memoizer

  before_action :dotcom_required, only: [
    :send_for_scanning,
    :send_for_batch_scan_for_user,
    :send_for_batch_scan_for_repository
  ]
  before_action :ensure_asset_exists, except: [:send_for_batch_scan_for_user, :send_for_batch_scan_for_repository]

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
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    render "stafftools/user_assets/show"
  end

  def destroy
    this_asset.purge

    instrument "staff.delete_user_asset", event_payload

    flash[:notice] = "Deleted image attachment with ID #{this_asset.id}."
    redirect_to stafftools_path
  end

  def send_for_scanning # rubocop:todo GitHub/UseRestfulActions
    GlobalInstrumenter.instrument "user_asset.scan_requested", {
      user_asset: this_asset,
    }

    flash[:notice] = "Sent asset for scanning"
    redirect_to stafftools_path
  end

  def send_for_batch_scan_for_user # rubocop:todo GitHub/UseRestfulActions
    return render_404 if this_user.nil?

    if this_user.assets.empty?
      return redirect_to stafftools_path
    end

    ScanUploadsJob.perform_later(target: this_user)

    payload = build_user_scan_payload(this_user)
    UserAsset.instrument_user_assets_batch_scan(payload)

    flash[:notice] = "Sent all of #{this_user}'s assets for scanning"
    redirect_to stafftools_path
  end

  def send_for_batch_scan_for_repository # rubocop:todo GitHub/UseRestfulActions
    return render_404 if this_repository.nil?

    if UserAsset.where(id: repository_asset_ids).empty?
      return redirect_to stafftools_path
    end

    ScanUploadsJob.perform_later(target: this_repository)

    payload = build_repo_scan_payload
    UserAsset.instrument_repository_assets_batch_scan(payload)

    flash[:notice] = "Sent all of #{this_repository.name}'s assets for scanning"
    redirect_to stafftools_path
  end

  private

  memoize def this_repository
    Repositories.domain.active_by_id(params[:repository_id]&.to_i)
  end

  memoize def repository_asset_ids
    Attachment.asset_ids_for_entity(this_repository)
  end

  def build_repo_scan_payload
    payload = {
      actor: "github-staff",
      repository: this_repository,
      repository_owner: this_repository.owner.to_s,
      number_of_assets: UserAsset.where(id: repository_asset_ids).count
    }

    payload.update(GitHub.guarded_audit_log_staff_actor_entry(current_user))
  end

  def build_user_scan_payload(user)
    payload = {
      actor: "github-staff",
      user: user.display_login,
      user_id: user.id,
      number_of_assets: user.assets.count
    }

    payload.update(GitHub.guarded_audit_log_staff_actor_entry(current_user))
  end

  def this_asset # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @this_asset ||= UserAsset.find_by(id: params[:id])
  end
  helper_method :this_asset

  def ensure_asset_exists
    render_404 if this_asset.nil?
  end

  def event_payload
    {
      asset_id: this_asset.id,
      asset_guid: this_asset.guid,
    }
  end
end
