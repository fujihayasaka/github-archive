# typed: true
# frozen_string_literal: true

class Stafftools::Users::AttachmentsController < StafftoolsController
  before_action :ensure_user_exists, :ensure_attachments_type

  layout "layouts/stafftools/user/content"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql2,
    only: [:index]

  VALID_ATTACHMENTS_TYPES = %i[user_assets repository_files].freeze

  def index
    attachments_type = params[:attachments_type].to_sym

    scope = attachments_type == :user_assets ? UserAsset.where(user_id: this_user.id) : RepositoryFile.where(uploader_id: this_user.id)
    attachments = scope
      .order(created_at: :desc)
      .paginate(page: params[:page] || 1)

    render "stafftools/users/attachments/index", locals: {
      attachments: attachments,
      attachments_type: attachments_type,
      target_user: this_user,
      actor: current_user
    }
  end

  def batch_destroy # rubocop:disable GitHub/UseRestfulActions
    type = params[:attachments_type]
    ids = params[:ids]

    case type
    when :user_assets
      DeleteUserAssetsByUserIdJob.perform_later(user_id: this_user.id, assets_ids: ids)
    when :repository_files
      DeleteRepositoryFilesByUserIdJob.perform_later(user_id: this_user.id, files_ids: ids)
    end

    flash_message_prefix = ids&.any? ? "Selected" : "All"
    redirect_to(
      stafftools_user_attachments_path(this_user, attachments_type: type),
      flash: { notice: "#{flash_message_prefix} attachments of type '%s' are being deleted in background. Check again in a few moments this page again to see if attachments were deleted with success." % type }
    )
  end

  private

  def ensure_attachments_type
    type = params[:attachments_type]&.to_sym || :user_assets

    if VALID_ATTACHMENTS_TYPES.include?(type)
      params[:attachments_type] = type
    else
      flash.now[:error] = "Attachment type '%s' not supported. Please change the URL query parameters to use 'user_assets' or 'repository_files'." % type
      render "stafftools/users/attachments/index", locals: {
        attachments: [],
        attachments_type: type,
        target_user: this_user,
        actor: current_user
      }
    end
  end
end
