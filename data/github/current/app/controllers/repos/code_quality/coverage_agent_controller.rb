# typed: strict
# frozen_string_literal: true

class Repos::CodeQuality::CoverageAgentController < Repos::CodeQuality::BaseRepositoryController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency

  GENERIC_START_ERROR_MESSAGE = "An error occurred while starting coverage setup. Please try again later."

  allow_verified_fetch only: [:create]

  before_action :ensure_feature_code_quality_enabled
  before_action :manage_code_quality_permission_required
  before_action :writable_repository_required

  sig { void }
  def create
    return head :not_found unless CodeCoverage.coverage_agent_enabled?(current_repository)

    ref_name = "refs/heads/#{current_repository.default_branch}"

    GitHub.logger.info("Starting coverage agent",
      "gh.repo.id": current_repository.id,
      "gh.owner.id": current_repository.owner.id,
      "gh.actor.id": current_user.id,
    )

    response_data = GitHub::Turboquality.check_error(
      GitHub::Turboquality.coverage_agent_client.start_coverage_agent(
        Turboquality::Proto::StartCoverageAgentRequest.new(
          repository_id: current_repository.id,
          owner_id: current_repository.owner.id,
          actor_id: current_user.id,
          ref_name_bytes: ref_name.b,
        )
      )
    )

    GitHub.dogstats.increment("code_quality.coverage_agent.create", tags: ["result:success"])
    render json: { jobId: response_data.job_id, pullRequestNumber: response_data.pull_request_number }
  rescue GitHub::Turboquality::ResponseError => e
    GitHub.logger.error("Coverage agent failed",
      "gh.repo.id": current_repository.id,
      "gh.owner.id": current_repository.owner.id,
      "gh.actor.id": current_user.id,
      "error.class": e.class.name,
      "error.message": e.message,
    )
    GitHub.dogstats.increment("code_quality.coverage_agent.create", tags: ["result:error"])
    render json: { message: GENERIC_START_ERROR_MESSAGE }, status: :unprocessable_entity
  end
end
