# typed: true
# frozen_string_literal: true

class EditRepositories::PullRequestCreationCapController < AbstractRepositoryController
  before_action :login_required
  before_action :ensure_admin_access
  before_action :writable_repository_required
  before_action :ensure_feature_enabled

  def toggle # rubocop:disable GitHub/UseRestfulActions
    config = PullRequestCreationConfig.new(current_repository)
    config.set_pull_request_creation_cap(
      enabled: params[:enable_pull_request_creation_cap] == "1",
      cap: config.pull_request_creation_cap,
      actor: current_user
    )

    head :ok
  end

  def update
    PullRequestCreationConfig.new(current_repository).set_pull_request_creation_cap(
      enabled: true,
      cap: params[:pull_request_creation_cap],
      actor: current_user
    )

    respond_to do |format|
      format.turbo_stream { render "edit_repositories/interaction_limits/pull_request_creation_cap_update", locals: { repository: current_repository } }
      format.html { redirect_to :back }
    end
  rescue ArgumentError => error
    flash[:error] = error.message
    respond_to do |format|
      format.turbo_stream { render "edit_repositories/interaction_limits/pull_request_creation_cap_update", locals: { repository: current_repository }, status: :unprocessable_entity }
      format.html { redirect_to :back }
    end
  end

  private

  def ensure_feature_enabled
    render_404 unless FeatureFlag.vexi.enabled?(:pull_request_creation_cap, current_repository, default: false)
  end
end
