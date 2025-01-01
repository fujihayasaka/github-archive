# typed: true
# frozen_string_literal: true

class EditRepositories::InteractionLimitsController < AbstractRepositoryController
  before_action :login_required
  before_action :writable_repository_required
  before_action :set_interaction_limits_permissions_required
  before_action :ensure_interaction_limits_enabled

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    ApplicationRecord::Memex,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    optional: true,
    only: [:show]

  def show
    permission = current_repository.async_action_or_role_level_for(current_user, include_custom_roles: false).sync
    render "edit_repositories/interaction_limits/show", locals: { permission: permission }
  end

  def update
    limit = InteractionLimits::SetInteractionLimit.enum_to_limit_name(
      params[:interaction_setting]
    )
    duration = if params[:expiry].present?
      params[:expiry].downcase.to_sym
    else
      :one_day
    end

    inputs = {
      object: current_repository,
      limit: limit,
      duration: duration,
      actor: current_user,
    }

    result = InteractionLimits::SetInteractionLimit.call(inputs)

    if result.success?
      flash[:notice] = "Repository interaction limit settings saved."
    else
      flash[:error] = result.error
    end

    redirect_to repository_interaction_limits_path(current_repository.owner, current_repository)
  end

  private

  def ensure_interaction_limits_enabled
    return render_404 unless GitHub.interaction_limits_enabled?
    render_404 if current_repository.private?
  end

  def set_interaction_limits_permissions_required
    render_404 unless current_repository.can_set_interaction_limits?(current_user)
  end
end
