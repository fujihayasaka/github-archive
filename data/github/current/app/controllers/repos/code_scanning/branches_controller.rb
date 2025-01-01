# typed: true
# frozen_string_literal: true

class Repos::CodeScanning::BranchesController < AbstractRepositoryController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:create]

  before_action :pushers_only
  before_action :login_required
  before_action :writable_repository_required
  before_action :try_parse_json_params
  before_action :require_code_scanning_alert_fix_journey_enabled, only: [:create]

  def create
    branch_name = Git::Ref.normalize(params[:name])
    alert_number = params[:number].to_i
    default_branch_ref = current_repository.default_branch_ref

    return render status: 422, json: { message: "Branch name is required" } if branch_name.blank?
    return render status: 422, json: { message: "Default branch must exist" } if default_branch_ref.nil?

    can_commit_to_branch = current_repository.can_commit_to_branch_status(current_user, branch_name)
    return render status: 422, json: { message: "You cannot commit to this branch" } if can_commit_to_branch != :allowed

    branch = current_repository.heads.find(branch_name)
    return render status: 422, json: { message: "Branch already exists" } if branch.present?

    branch = current_repository.heads.create(branch_name, default_branch_ref.commit.oid, current_user, reflog_data: request_reflog_data("web branch create from on demand"))

    # the `b` method on branch changes the encoding to ASCII-8BIT
    response = GitHub::Turboscan.create_alert_links(
      repository_id: current_repository.id,
      links: [
        {
          alert_number: alert_number,
          ref_name_bytes: branch.qualified_name.b,
        }
      ]
    )

    if response.blank? || response.error.present?
      error_message = response&.error&.msg&.include?("not all alerts were found") ? "Could not find the alert" : "Something went wrong"
      return render status: 422, json: { message: error_message }
    end

    render json: {
      branchName: branch_name,
      messages: [],
    }, status: 200
  rescue Git::Ref::InvalidName
    render status: 422, json: { message: "Invalid branch name" }
  rescue Git::Ref::ExistsError
    render status: 422, json: { message: "Branch already exists" }
  rescue Git::Ref::UpdateError
    render status: 422, json: { message: "Could not create branch" }
    # Rulesets might prevent the ref from being created, we may consider rescuing it in the future (https://github.com/github/code-scanning/issues/15893)
  end

  private

  def require_code_scanning_alert_fix_journey_enabled
    render_404 unless current_repository.feature_enabled?(:code_scanning_alert_fix_journey)
  end
end
