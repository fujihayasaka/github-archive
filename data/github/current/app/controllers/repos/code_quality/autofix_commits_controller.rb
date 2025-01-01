# typed: strict
# frozen_string_literal: true

class Repos::CodeQuality::AutofixCommitsController < Repos::CodeQuality::BaseRepositoryController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency

  before_action :pushers_only
  before_action :try_parse_json_params
  before_action :check_code_quality_read

  allow_verified_fetch only: [:create]

  sig { void }
  def create
    finding_stable_id = params[:finding_stable_id]

    name = Git::Ref.normalize(params[:name])
    create_new_branch = ActiveModel::Type::Boolean.new.cast(params.fetch(:create_new_branch, true))
    create_draft_pr = ActiveModel::Type::Boolean.new.cast(params.fetch(:create_draft_pr, false))
    commit_message = params[:commit_message]
    extended_description = params[:extended_description]

    return render status: 422, json: { message: "Branch name is required" } if name.blank?
    return render status: 422, json: { message: "Commit message is required" } if commit_message.blank?
    return render status: 422, json: { message: "Default branch must exist" } if current_repository.default_branch_ref.nil?

    default_branch_ref = current_repository.default_branch_ref

    response = GitHub::Turboquality.client.get_suggested_fixes(Turboquality::Proto::GetSuggestedFixesRequest.new(
      repository_id: current_repository.id,
      finding_stable_ids: [finding_stable_id],
    ))
    raise StandardError.new(response.error.to_s) if response.error

    suggested_fix = response.data.fixes.to_a.first
    return render status: 404, json: { message: "No autofix found for this finding" } if suggested_fix.nil?

    suggested_fix_state = suggested_fix.state
    suggested_fix_state = Turboquality::Proto::SuggestedFixState.resolve(suggested_fix_state) if suggested_fix_state.is_a?(Symbol)

    unless suggested_fix_state == Turboquality::Proto::SuggestedFixState::SUGGESTED_FIX_STATE_VALID
      return render status: 404, json: { message: "No valid autofix found for this finding" }
    end

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
      branch = current_repository.heads.create(name, default_branch_ref.commit.oid, current_user, reflog_data: request_reflog_data("web branch create from code quality on demand"))
    end

    code_scanning_app = Apps::Privileged.integration(:code_scanning)
    raise "Code scanning integration not installed!" if code_scanning_app.nil?

    full_commit_message = [commit_message, extended_description].compact.join("\n\n")

    diff_entries = suggested_fix.files.each_with_object([]) do |file, entries|
      parser = GitHub::Diff::Parser.new(file.diff_content)
      parser.each do |entry|
        entries << entry
      end
    rescue GitHub::Diff::Parser::UnrecognizedText => err
      # report the error to Sentry
      Failbot.report!(err)
      return render status: 500, json: { message: "Something went wrong while constructing the autofix" }
    end

    if diff_entries.empty?
      return render status: 500, json: { message: "Something went wrong while constructing the autofix" }
    end

    suggested_change = DiffEntrySuggestedChange.new(repository: current_repository, ref: branch, diff_entries:)
    suggested_change.commit_change_for_user(
      author: current_user,
      current_oid: branch.commit.oid,
      message: full_commit_message,
      sign: true,
      co_author_note: "Co-authored-by: Copilot Autofix powered by AI <#{code_scanning_app.bot.git_author_email}>",
      reflog_data: {
        repo_name: suggested_change.repository.name_with_display_owner,
        repo_public: suggested_change.repository.public?,
        user_login: code_scanning_app.bot.display_login,
        from: GitHub.context[:from],
        via: "apply code quality autofix suggestion from on demand",
      }
    )

    pull_request = current_repository.pull_requests.open_pulls
      .where(
        head_repository_id: current_repository.id, # Ignore PRs from forks
        base_repository_id: current_repository.id,
        head_ref: Git::Ref.safe_ref_name(ref_names: name)
      )
      # It shouldn't be possible to have multiple open PRs for the same branch,
      # but if there are we then let's just link to the most recent one
      .order(created_at: :desc)
      .first # domain-isolation-query-violation:ignore:packages/issues (SELECT)

    if create_draft_pr
      begin
        pull_request ||= PullRequest.create_for!(current_repository, {
          user: current_user,
          base: current_repository.default_branch,
          head: branch.name,
          draft: true,
          title: commit_message,
          body: "#{[extended_description, suggested_fix.description].compact.join("\n\n")}\n\n_Suggested fixes powered by Copilot Autofix. Review carefully before merging._",
        })
      rescue StandardError => err # rubocop:todo Lint/RescueException
        Failbot.report(err)
        return render status: 422, json: { message: "Something went wrong during PR creation" }
      end
    end

    analytics_event(
      category: "code_quality",
      action: "#{create_new_branch ? "create" : "update"}_branch",
      label: {
        finding_stable_id: finding_stable_id,
        create_draft_pr: create_draft_pr,
        repository_id: current_repository.id,
        org_id: current_repository.owner_id,
        pull_request_id: pull_request&.id,
      },
    )

    pull_request_payload = {
      number: pull_request.number,
      repository: {
        ownerLogin: current_repository.owner_display_login,
        name: current_repository.name,
      },
    } if pull_request

    render json: {
      branchName: name,
      pullRequest: pull_request_payload,
      messages: [],
    }
  rescue DiffEntrySuggestedChange::Error => e
    render status: 422, json: { message: e.message }
  rescue Git::Ref::InvalidName
    render status: 422, json: { message: "Invalid branch name" }
  rescue Git::Ref::ExistsError
    render status: 422, json: { message: "Branch already exists" }
  rescue Git::Ref::UpdateError
    render status: 422, json: { message: "Could not create branch" }
  end
end
