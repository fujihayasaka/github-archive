# typed: true
# frozen_string_literal: true

class Repos::SecurityCampaigns::AlertBranchesController < Repos::SecurityCampaigns::BaseRepositoryController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include SecurityCampaigns::AutofixApplyHelper

  before_action :check_code_scanning_write
  before_action :pushers_only, only: [:create]
  before_action :try_parse_json_params, only: [:create]

  allow_verified_fetch only: [:create]

  def create
    campaign = if T.must(current_user).feature_enabled?(:security_campaigns_read_without_alerts_limit)
      SecurityCampaigns::SecurityCampaign.open.
        find_by(number: params[:number], organization: current_repository.owner_id)
    else
      SecurityCampaigns::SecurityCampaign.open.
        for_repo_with_alerts(current_repository).
        find_by(number: params[:number], organization: current_repository.owner_id)
    end

    return render_404 if campaign.nil?
    return render status: 422, json: { message: "Campaign is closed" } if campaign.closed?

    name = Git::Ref.normalize(params[:name])
    create_new_branch = ActiveModel::Type::Boolean.new.cast(params.fetch(:create_new_branch, true))
    alert_numbers = params[:alert_numbers]
    commit_autofix_suggestions = ActiveModel::Type::Boolean.new.cast(params.fetch(:commit_autofix_suggestions, false))
    create_draft_pr = ActiveModel::Type::Boolean.new.cast(params.fetch(:create_draft_pr, false))

    # We should only commit suggested fixes if the feature is enabled for the repository
    commit_suggested_fixes = commit_autofix_suggestions && CodeScanning::Autofix.any_enabled_for_repo?(current_repository)

    return render status: 422, json: { message: "Branch name is required" } if name.blank?
    return render status: 422, json: { message: "Alert numbers are required" } if alert_numbers.blank? || !alert_numbers.is_a?(Array)
    return render status: 422, json: { message: "Default branch must exist" } if current_repository.default_branch_ref.nil?
    return render status: 422, json: { message: "Must make a new branch or commit autofix suggestions" } if !create_new_branch && !commit_autofix_suggestions

    alert_numbers = alert_numbers.map(&:to_i)

    return render status: 422, json: { message: "Invalid alert numbers" } unless alert_numbers.all?(&:positive?)

    # Find all open alerts that match the given alert numbers
    campaign_with_alerts = SecurityCampaigns::CampaignWithAlerts.load_campaign(
      campaign, repo: current_repository, user: current_user, user_session: user_session,
      alert_numbers: { current_repository.id => alert_numbers },
      query_string: "is:open",
    )
    alerts = campaign_with_alerts.turboscan_alerts

    if T.must(current_user).feature_enabled?(:security_campaigns_read_without_alerts_limit) &&
      campaign_with_alerts.open_count == 0 && campaign_with_alerts.closed_count == 0
      return render_404
    end

    default_branch_ref = current_repository.default_branch_ref
    current_commit = default_branch_ref.commit

    author_email = current_user.default_author_email(current_repository)
    if author_email && !current_user.author_emails.include?(author_email)
      return render status: 422, json: { message: "Invalid email for web commit" }
    end

    commit_oid = current_commit.oid

    branch = current_repository.heads.find(name)

    can_commit_to_branch = current_repository.can_commit_to_branch_status(current_user, name)
    return render status: 422, json: { message: "You cannot commit to this branch" } if can_commit_to_branch != :allowed

    if create_new_branch && !branch.nil?
      return render status: 422, json: { message: "Branch already exists" }
    elsif !create_new_branch && branch.nil?
      return render status: 422, json: { message: "Branch does not exist" }
    end

    if create_new_branch
      branch = current_repository.heads.create(name, commit_oid, current_user, reflog_data: request_reflog_data("web branch create from security campaign"))
    end

    pull_request = current_repository.pull_requests.open_pulls.
      where(
        head_repository_id: current_repository.id, # Ignore PRs from forks
        base_repository_id: current_repository.id,
        head_ref: Git::Ref.safe_ref_name(ref_names: name),
      ).
      # It shouldn't be possible to have multiple open PRs for the same branch,
      # but if there are then let's just take the most recent one
      order(created_at: :desc).
      first

    messages = []

    if commit_suggested_fixes
      # Get all fixes for these alerts
      suggested_fixes = CodeScanning::Autofix.suggested_fixes_for_alerts(
        current_repository,
        alerts.map(&:result).map(&:number).uniq,
        ref: default_branch_ref,
        head_commit: branch.commit,
      )

      messages = apply_multiple_autofix_suggestions(
        suggested_fixes,
        alerts:,
        repository: current_repository,
        ref: branch,
        author: current_user,
        author_email:,
        reflog_data: request_reflog_data("apply autofix suggestion from security campaign"),
        user_commit_message: alert_numbers.count == 1 ? commit_message : nil,
      )

      if create_draft_pr && pull_request.nil?
        begin
          pull_request = commit_to_pr(
            suggested_fixes:,
            alerts:,
            user: current_user,
            repository: current_repository,
            branch:
          )
        rescue StandardError # rubocop:todo Lint/GenericRescue
          return render status: 422, json: { message: "Something went wrong during PR creation" }
        end
      end
    end

    if pull_request.nil?
      GitHub::Turboscan.create_alert_links(
        repository_id: current_repository.id,
        alert_numbers:,
        ref_name_bytes: branch.qualified_name.b,
      )
    else
      GitHub::Turboscan.create_alert_links(
        repository_id: current_repository.id,
        alert_numbers:,
        pull_request_id: pull_request.id,
      )
    end

    analytics_event(
      category: "security_campaigns",
      action: "#{create_new_branch ? "create" : "update"}_branch",
      label: {
        security_campaign_id: campaign.id,
        alert_numbers_count: alert_numbers.size,
        commit_suggested_fixes: commit_suggested_fixes,
        create_draft_pr: create_draft_pr,
      },
    )

    pull_request_path = pull_request ? gh_show_pull_request_path(pull_request) : nil

    render json: {
      branchName: name,
      pullRequestPath: pull_request_path,
      messages:,
    }, status: 200
  rescue Git::Ref::InvalidName
    render status: 422, json: { message: "Invalid branch name" }
  rescue Git::Ref::ExistsError
    render status: 422, json: { message: "Branch already exists" }
  rescue Git::Ref::UpdateError
    render status: 422, json: { message: "Could not create branch" }
  end

  private

  def commit_message
    commit_message = params[:commit_message]
    extended_description = params[:extended_description]

    if commit_message.present?
      return commit_message + (extended_description.present? ? "\n\n#{extended_description}" : "")
    end

    nil
  end
end
