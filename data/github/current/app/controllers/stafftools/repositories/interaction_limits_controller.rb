# typed: true
# frozen_string_literal: true

class Stafftools::Repositories::InteractionLimitsController < Stafftools::RepositoriesController

  def update
    return render_404 unless GitHub.interaction_limits_enabled?

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
      staff_actor: true,
    }

    result = InteractionLimits::SetInteractionLimit.call(inputs)

    if result.success?
      flash[:notice] = "Interaction limit settings saved."
    else
      flash[:error] = result.error
    end

    redirect_to gh_admin_stafftools_repository_path(current_repository)
  end
end
