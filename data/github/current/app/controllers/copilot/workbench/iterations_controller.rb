# typed: strict
# frozen_string_literal: true

class Copilot::Workbench::IterationsController < Copilot::Workbench::AbstractWorkbenchController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  allow_verified_fetch

  before_action :try_parse_json_params
  before_action :require_workbench

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    only: [:index]

  sig { void }
  def index
    iterations = T.must(workbench).iterations
    current_iteration_id = T.must(workbench).current_iteration_id

    render json: { iterations:, current_iteration_id: }, status: :ok
  end

  sig { void }
  def create
    iteration = Workbench::Iterations::Create.perform(T.must(workbench), iteration_params.to_h)

    if iteration.persisted?
      render json: { iteration: }, status: :created
    else
      render json: { errors: iteration.errors }, status: :unprocessable_entity
    end
  end

  sig { void }
  def update
    iteration = T.must(workbench).iterations.find_by(id: params[:iteration_id])
    return render_404 unless iteration

    Workbench::Iterations::Update.perform(T.must(workbench), iteration, iteration_params.to_h)

    if iteration.valid?
      render json: { iteration: }, status: :ok
    else
      render json: { errors: iteration.errors }, status: :unprocessable_entity
    end
  end

  private

  sig { returns T.nilable(Spark::Workbench) }
  memoize def workbench
    Spark::Workbench.for_uuid_string(current_user.id, params[:id])
  end

  sig { returns(ActionController::Parameters) }
  def iteration_params
    params.require(:iteration).permit(:prompt, :iteration_type, :sha, files: {}, suggestions: [])
  end

  sig { void }
  def require_workbench
    render_404 unless workbench
  end
end
