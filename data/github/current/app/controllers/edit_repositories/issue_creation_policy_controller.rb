# typed: true
# frozen_string_literal: true

class EditRepositories::IssueCreationPolicyController < AbstractRepositoryController
  before_action :login_required
  before_action :ensure_admin_access
  before_action :writable_repository_required
  before_action :ensure_feature_enabled

  def update
    policy = params[:issue_creation_policy]
    update_success = false

    begin
      IssueCreationConfig.new(current_repository).set_issue_creation_policy(
        policy: policy,
        actor: current_user
      )
      update_success = true
    rescue ArgumentError
      update_success = false
    end

    respond_to do |format|
      format.turbo_stream do
        render "edit_repositories/issue_creation_policy/update", locals: { update_success: update_success }
      end

      format.html do
        if request.xhr?
          head :ok
        else
          redirect_to :back
        end
      end

      format.all do
        head :ok
      end
    end
  end

  private

  def ensure_feature_enabled
    unless FeatureFlag.vexi.enabled?(:issue_creation_restriction_settings, current_repository, default: false)
      render_404
    end
  end
end
