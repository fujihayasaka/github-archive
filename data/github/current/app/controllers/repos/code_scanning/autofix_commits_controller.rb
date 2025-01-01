# typed: true
# frozen_string_literal: true

class Repos::CodeScanning::AutofixCommitsController < AbstractRepositoryController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::PartialRenderWithLayoutDependency
  include CodeScanning::ResultDependency

  allow_verified_fetch only: [:create]

  before_action :pushers_only
  before_action :try_parse_json_params
  before_action :login_required
  before_action :writable_repository_required

  preload_features [
    :disable_code_scanning
  ]

  def create
    unless CodeScanning::Autofix.any_enabled_for_repo?(current_repository)
      return render status: 422, json: { message: "Autofix is not enabled for repository" }
    end

    name = Git::Ref.normalize(params[:name])
    create_new_branch = ActiveModel::Type::Boolean.new.cast(params.fetch(:create_new_branch, true))
    alert_number = params[:number].to_i
    create_draft_pr = ActiveModel::Type::Boolean.new.cast(params.fetch(:create_draft_pr, false))

    return render status: 422, json: { message: "Branch name is required" } if name.blank?
    return render status: 422, json: { message: "Default branch must exist" } if current_repository.default_branch_ref.nil?

    default_branch_ref = current_repository.default_branch_ref

    alert = GitHub::Turboscan.alert(
      repository_id: current_repository.id,
      number: alert_number,
      ref_names_bytes: [default_branch_ref.qualified_name]
    )&.data&.result

    return render status: 422, json: { message: "Couldn't find the alert" } if alert.nil?

    author_email = current_user.default_author_email(current_repository)
    if author_email && !current_user.author_emails.include?(author_email)
      return render status: 422, json: { message: "Invalid email for web commit" }
    end

    branch = current_repository.heads.find(name)
    can_commit_to_branch = current_repository.can_commit_to_branch_status(current_user, name)
    return render status: 422, json: { message: "You cannot commit to this branch" } if can_commit_to_branch != :allowed

    if create_new_branch && branch.present?
      return render status: 422, json: { message: "Branch already exists" }
    elsif !create_new_branch && branch.blank?
      return render status: 422, json: { message: "Branch does not exist" }
    end

    if create_new_branch
      branch = current_repository.heads.create(name, default_branch_ref.commit.oid, current_user, reflog_data: request_reflog_data("web branch create from on demand"))
    end

    pull_request = current_repository.pull_requests.open_pulls
      .where(
        head_repository_id: current_repository.id, # Ignore PRs from forks
        base_repository_id: current_repository.id,
        head_ref: Git::Ref.safe_ref_name(ref_names: name)
      )
      # It shouldn't be possible to have multiple open PRs for the same branch,
      # but if there are we then let's just link to the most recent one
      .order(created_at: :desc)
      .first

    suggested_fix = CodeScanning::AutofixSuggestion.fetch_suggested_fix(
      repository: current_repository,
      alert_number: alert_number,
      head_commit_oid: branch.commit.oid
    )

    alert_title = result_title(alert)
    alert_link = UrlHelpers.repository_code_scanning_result_url(current_repository.owner, current_repository, number: alert_number, host: GitHub.url)
    description = CodeScanning::AutofixCommit.pull_request_description(alert_link, suggested_fix.description)

    CodeScanning::AutofixCommit.create(
      alert_number:,
      commit_message: construct_commit_message,
      repository: current_repository,
      ref: branch,
      author: current_user,
      suggested_fix: suggested_fix,
      reflog_via: "apply autofix suggestion from on demand"
    )

    if create_draft_pr
      begin
        pull_request ||= PullRequest.create_for!(current_repository, {
          user: current_user,
          base: current_repository.default_branch,
          head: branch.name,
          draft: true,
          title: CodeScanning::AutofixCommit.pr_title(alert_number:, alert_title:),
          body: description,
        })
      rescue StandardError # rubocop:todo Lint/GenericRescue
        return render status: 422, json: { message: "Something went wrong during PR creation" }
      end
    end

    if pull_request.present?
      GitHub::Turboscan.create_alert_links(
        repository_id: current_repository.id,
        alert_numbers: [alert_number],
        pull_request_id: pull_request.id
      )

      GlobalInstrumenter.instrument("code_scanning.autofix_remediation_intent_event", {
        repository_id: current_repository.id,
        logical_alert_number: alert_number,
        analysis_ref: current_repository.default_branch_ref.qualified_name,
        event_type: :AUTOFIX_REMEDIATION_INTENT_EVENT_TYPE_PR,
        pull_request_id: pull_request.id
      })
    else
      GitHub::Turboscan.create_alert_links(
        repository_id: current_repository.id,
        alert_numbers: [alert_number],
        ref_name_bytes: branch.qualified_name.b
      )
    end

    pull_request_path = pull_request ? gh_show_pull_request_path(pull_request) : nil

    render json: {
      branchName: name,
      pullRequestPath: pull_request_path,
      messages: [],
    }, status: 200
  rescue CodeScanning::AutofixError, DiffEntrySuggestedChange::Error => e
    render status: 422, json: { message: e.message }
  rescue Git::Ref::InvalidName
    render status: 422, json: { message: "Invalid branch name" }
  rescue Git::Ref::ExistsError
    render status: 422, json: { message: "Branch already exists" }
  rescue Git::Ref::UpdateError
    render status: 422, json: { message: "Could not create branch" }
    # Rulesets might prevent the ref from being created, we may consider rescuing it in the future (https://github.com/github/code-scanning/issues/15893)
  end

  private

  def construct_commit_message
    commit_message = params[:commit_message]
    extended_description = params[:extended_description]

    return unless commit_message.present?

    [commit_message, extended_description].compact.join("\n\n")
  end
end
