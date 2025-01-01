# typed: true
# frozen_string_literal: true

class GitHubModels::AttachmentsController < ApplicationController
  before_action :login_required
  before_action :require_feature
  before_action :github_models_required
  before_action :require_models_attachment

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::GitHubModels,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries

  def show
    models_attachment = T.must_because(self.models_attachment) { "#require_models_attachment ensures non-nil" }
    storage_policy = models_attachment.storage_policy(actor: current_user)
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

  sig { returns T.nilable(GitHubModels::Attachment) }
  memoize def models_attachment
    GitHubModels::Attachment.uploaded.uploaded_by(current_user).find_by(id: params[:id])
  end

  def require_models_attachment
    render_404 unless models_attachment
  end

  def require_feature
    render_404 unless user_feature_enabled?(:github_models_uploadable_attachments)
  end
end
