# typed: strict
# frozen_string_literal: true

class Copilot::Workbench::DeploymentController < Copilot::Workbench::AbstractWorkbenchController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  allow_verified_fetch

  before_action :try_parse_json_params, only: [:update]
  before_action :require_workbench, only: [:update]

  sig { void }
  def update
    return render_404 unless maybe_workbench

    workbench = T.must(maybe_workbench)
    return render_404 unless workbench.runtime_app

    runtime_app = T.must(workbench.runtime_app)

    updated_fields = {}

    if params.key?(:visibility)
      original_visibility = runtime_app.visibility
      original_visibility_organization_id = runtime_app.visibility_organization_id
      new_visibility = params[:visibility]
      new_visibility_organization_id = nil

      if new_visibility == "github"
        # Validate if user can deploy to all GitHub users (includes EMU and CE license restrictions)
        unless can_deploy_to_all_github?
          render json: {
            error: "GitHub visibility not supported for enterprise managed accounts or Copilot Enterprise users"
          }, status: :forbidden
          return
        end
      elsif new_visibility == "selected_orgs"
        new_visibility_organization_id = params[:visibility_organization_id]
        return render_404 unless new_visibility_organization_id.present?
        organization = Organization.find_by(id: new_visibility_organization_id)
        return render_404 unless organization
        # Also ensure that the user has access to it and didn't pass in a random org ID
        return render_404 unless organization.member?(current_user)
      end

      updated_fields[:visibility] = new_visibility
      updated_fields[:visibility_organization_id] = new_visibility_organization_id
    end

    if params.key?(:read_only_kv)
      read_only_kv = params[:read_only_kv]
      if runtime_app.read_only_kv != read_only_kv
        GitHub.logger.info(
          "code.namespace": "Copilot::Workbench::DeploymentController",
          "message": "read_only_kv_change_detected",
          "read_only_kv": read_only_kv,
          "user_id": current_user.id,
          "workbench_id": workbench.id,
          "runtime_app_id": runtime_app.id,
          "visibility": runtime_app.visibility,
        )
      end

      updated_fields[:read_only_kv] = read_only_kv
    end

    if updated_fields.any?
      runtime_app.update!(updated_fields)

      # perform operations after db update
      if params.key?(:visibility)
        SparkRuntime::AcaInterface.notify_settings_changes(current_user, workbench)

        SparkRuntime::AcaInterface.purge_auth_for_app(
          current_user,
          runtime_app.permanent_name) if SparkRuntime::AcaInterface.needs_purge_auth?(original_visibility, new_visibility, original_visibility_organization_id, new_visibility_organization_id)
      end

      render json: updated_fields, status: :ok
    else
      render_404
    end
  end

  private

  sig { returns T.nilable(Spark::Workbench) }
  memoize def maybe_workbench
    Spark::Workbench.for_uuid_string(current_user.id, params[:id])
  end

  sig { returns(T::Boolean) }
  def can_deploy_to_all_github?
    return true unless current_user

    # If the feature flag is disabled, allow all users to deploy to GitHub
    return true unless current_user.feature_flag_enabled?(:spark_emu_deploy_to_github, default: false)

    # EMU users should never be able to deploy to all GitHub users
    !current_user.is_enterprise_managed?
  end

  sig { void }
  def require_workbench
    render_404 unless maybe_workbench
  end
end
