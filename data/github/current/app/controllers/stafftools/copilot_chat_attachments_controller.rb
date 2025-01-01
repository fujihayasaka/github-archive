# typed: true
# frozen_string_literal: true

class Stafftools::CopilotChatAttachmentsController < StafftoolsController
  include GitHub::Memoizer

  before_action :ensure_asset_exists

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:show]

  def show
    render "stafftools/copilot_chat_attachments/show"
  end

  def destroy
    this_asset.destroy

    instrument "staff.delete_copilot_chat_attachment", event_payload

    flash[:notice] = "Deleted chat attachment with ID #{this_asset.id}."
    redirect_to stafftools_path
  end

  private

  memoize def this_asset
    Copilot::ChatAttachment.find_by(id: params[:id])
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
