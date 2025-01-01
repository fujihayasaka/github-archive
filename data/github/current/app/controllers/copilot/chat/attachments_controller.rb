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
    Copilot::ChatAttachment.uploaded.uploaded_by(current_user).find_by(id: params[:id])
  end

  def require_chat_attachment
    render_404 unless chat_attachment
  end

  def require_feature_enabled
    render_404 unless user_feature_enabled?(:copilot_chat_attachments)
    super
  end
end
