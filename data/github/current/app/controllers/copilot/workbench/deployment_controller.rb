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
    runtime_app.update!(visibility: params[:visibility])

    render json: { visibility: params[:visibility] }, status: :ok
  end

  private

  sig { returns T.nilable(Spark::Workbench) }
  memoize def maybe_workbench
    Spark::Workbench.for_uuid_string(current_user.id, params[:id])
  end

  sig { void }
  def require_workbench
    render_404 unless maybe_workbench
  end
end
