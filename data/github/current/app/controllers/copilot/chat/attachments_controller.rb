# typed: true
# frozen_string_literal: true

class Copilot::Chat::AttachmentsController < Copilot::Chat::AbstractChatController
  before_action :require_chat_attachment

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IamAbilities

  def show
    chat_attachment = T.must_because(self.chat_attachment) { "#require_chat_attachment ensures non-nil" }
    storage_policy = chat_attachment.storage_policy(actor: current_user)
    url = storage_policy.download_url

    if request.xhr? || request.format.json?
      render json: { url: url }
    else
      redirect_to url
    end
  end

  private

  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    current_user
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end

  sig { returns T.nilable(Copilot::ChatAttachment) }
  memoize def chat_attachment
    attachment = Copilot::ChatAttachment.uploaded.includes(:uploader, copilot_space_resources: :copilot_space).find_by(guid: params[:id])
    attachment if user_allowed?(current_user, attachment)
  end

  sig do
    params(
      user: User,
      attachment: T.nilable(Copilot::ChatAttachment)
    ).returns(T::Boolean)
  end
  def user_allowed?(user, attachment)
    return false if attachment.nil?
    return true if attachment.uploader == user

    if FeatureFlag.vexi.enabled?(:copilot_spaces_duplicate, current_user, default: false) && copilot_space_id.present?
      copilot_space = CopilotSpace
        # Critical: only find the space if it is associated with this attachment
        .with_chat_attachment(attachment)
        .find_by(id: copilot_space_id)
      return true if copilot_space&.readable_by?(current_user)
    else
      return true if attachment.copilot_space_resources.first&.copilot_space&.readable_by?(user)
    end

    false
  end

  # This is an optional query param that is passed when viewing the attachment from a Copilot Space.
  # It is used to determine if the user has access to the Copilot Space associated with the attachment.
  def copilot_space_id
    params[:copilot_space_id]
  end

  def require_chat_attachment
    render_404 unless chat_attachment
  end

  def require_feature_enabled
    render_404 unless user_feature_enabled?(:copilot_chat_attachments)
    super
  end
end
