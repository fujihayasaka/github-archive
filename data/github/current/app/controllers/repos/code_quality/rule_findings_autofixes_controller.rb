# typed: strict
# frozen_string_literal: true

class Repos::CodeQuality::RuleFindingsAutofixesController < Repos::CodeQuality::BaseRepositoryController
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:create]

  before_action :check_code_quality_write

  sig { void }
  def create
    finding_stable_id = params[:finding_stable_id]
    rule_id = params[:rule_id]

    response = GitHub::Turboquality.client.generate_fix(Turboquality::Proto::GenerateFixRequest.new(
      commit_oid: current_repository.default_branch_ref.commit.oid,
      repository_id: current_repository.id,
      rule_id:,
      finding_stable_id:,
    ))

    return render status: :internal_server_error, json: { message: "An error occurred while generating an autofix, please try again later." } if response.error

    analytics_event(
      category: "code_quality",
      action: "generate_fix",
      label: {
        finding_stable_id: finding_stable_id,
        repository_id: current_repository.id,
        org_id: current_repository.owner_id,
        rule_id:,
      },
    )
    render json: {}, status: :ok
  end
end
