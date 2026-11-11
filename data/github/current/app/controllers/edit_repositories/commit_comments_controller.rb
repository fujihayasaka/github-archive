# typed: true
# frozen_string_literal: true

class EditRepositories::CommitCommentsController < AbstractRepositoryController
  before_action :login_required
  before_action :ensure_admin_access
  before_action :writable_repository_required
  before_action :ensure_feature_enabled
  before_action :add_spamurai_form_signals, only: [:update]

  def update
    commit_comments_config = CommitCommentsConfig.new(current_repository)
    if params[:has_commit_comments] == "1"
      commit_comments_config.enable_commit_comments(actor: current_user)
    else
      commit_comments_config.disable_commit_comments(actor: current_user)
    end

    head :ok
  end

  private

  def ensure_feature_enabled
    unless FeatureFlag.vexi.enabled?(:configure_commit_comments, current_repository, default: false)
      render_404
    end
  end
end
