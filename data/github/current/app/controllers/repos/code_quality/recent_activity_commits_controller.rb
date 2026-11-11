# typed: strict
# frozen_string_literal: true

class Repos::CodeQuality::RecentActivityCommitsController < Repos::CodeQuality::BaseRepositoryController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include ActionView::Helpers::TextHelper

  before_action :pushers_only
  before_action :try_parse_json_params
  before_action :check_code_quality_read
  before_action :ensure_feature_code_quality_enabled

  allow_verified_fetch only: [:create]

  sig { void }
  def create
    fixes = params[:fixes]
    return render status: 422, json: { message: "Findings fixes are required" } if fixes.blank? || !fixes.is_a?(Array)

    fixes.each do |fix|
      return render status: 422, json: { message: "Each fix must include a file path and diff content" } unless fix.key?("file_path") && fix.key?("diff_content")
      return render status: 422, json: { message: "File path and diff content cannot be blank" } if fix["file_path"].blank? || fix["diff_content"].blank?
    end

    name = Git::Ref.normalize(params[:name])
    create_new_branch = ActiveModel::Type::Boolean.new.cast(params.fetch(:create_new_branch, true))
    create_draft_pr = ActiveModel::Type::Boolean.new.cast(params.fetch(:create_draft_pr, false))

    return render status: 422, json: { message: "Branch name is required" } if name.blank?
    return render status: 422, json: { message: "Default branch must exist" } if current_repository.default_branch_ref.nil?

    default_branch_ref = current_repository.default_branch_ref

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

    code_quality_app = Apps::Privileged.integration(:code_quality)
    raise "Code quality integration not installed!" if code_quality_app.nil?

    proposed_commits = fixes.map do |fix|
      parser = GitHub::Diff::Parser.new(fix["diff_content"])
      diff_entries = T.let([], T::Array[GitHub::Diff::Entry])
      parser.each do |entry|
        diff_entries << entry
      end

      if diff_entries.empty?
        return render status: 422, json: { message: "Diff entries cannot be empty" }
      end

      lines = T.let([], T::Array[GitHub::Diff::Line])
      diff_entry = T.must(diff_entries.first)
      diff_entry.basic_enumerator.each do |line|
        next unless line.addition? || line.deletion?
        lines << line
      end

      CodeQuality::ProposedCommit.new(
        commit_message: "Apply suggested fix to #{fix["file_path"]} from Copilot Autofix",
        diff_entry: diff_entry,
        diff_lines: lines,
      )
    rescue GitHub::Diff::Parser::UnrecognizedText => err
      return render status: 422, json: { message: "Invalid diff content" }
    end

    # Sort proposed commits so that later changes in the file are prioritized to avoid potential conflicts
    proposed_commits = proposed_commits.sort_by do |proposed_commit|
      [proposed_commit.diff_entry.path, -proposed_commit.left_start_line, -proposed_commit.right_start_line, -proposed_commit.left_end_line, -proposed_commit.right_end_line]
    end

    # Filter out overlapping commits
    messages = []
    proposed_commits_filter = CodeQuality::ProposedCommitsFilter.new(proposed_commits)
    if proposed_commits_filter.rejected_commits.any?
      messages << "#{proposed_commits_filter.rejected_commits.size} #{"autofix".pluralize(proposed_commits_filter.rejected_commits.size)} #{"was".pluralize(proposed_commits_filter.rejected_commits.size)} not applied due to conflicts."
    end

    # Retrieve all blobs in advance and store them in a hash. This will allow us to only retrieve each blob once, and
    # update the content in-memory as we apply changes instead of needing to re-fetch the blob from Spokes for each
    # commit. This also prevents errors related to replication-lag/read-after-write consistency when applying multiple
    # commits to the same file.
    file_paths = proposed_commits_filter.accepted_commits.map(&:diff_entry).map(&:path).uniq
    blobs = file_paths.map do |file_path|
      blob = current_repository.blob(branch.commit.oid, file_path, { truncate: false, limit: 1.megabyte })
      if blob.blank?
        raise DiffEntrySuggestedChange::NotFoundError.new("This diff has recently been updated.")
      end
      [file_path, blob]
    end
    blobs = blobs.to_h

    current_commit_oid = branch.commit.oid
    proposed_commits_filter.accepted_commits.each do |proposed_commit|
      suggested_change = DiffEntrySuggestedChange.new(repository: current_repository, ref: branch, diff_entries: [proposed_commit.diff_entry])

      files = suggested_change.build_new_files(blobs:)

      result = suggested_change.commit_change_for_user(
        author: current_user,
        files:,
        current_oid: current_commit_oid,
        message: proposed_commit.commit_message,
        sign: true,
        co_author_note: "Co-authored-by: Copilot Autofix powered by AI <#{code_quality_app.bot.git_author_email}>",
        reflog_data: {
          repo_name: suggested_change.repository.name_with_display_owner,
          repo_public: suggested_change.repository.public?,
          user_login: code_quality_app.bot.display_login,
          from: GitHub.context[:from],
          via: "apply code quality autofix suggestion from on demand",
        }
      )

      # Update our in-memory blobs with the new file contents
      files.each do |file_path, file_content|
        blobs[file_path].data = file_content
      end

      current_commit_oid, _branch, _error = result
    rescue GitHub::Diff::Parser::UnrecognizedText => err
      return render status: 422, json: { message: "Invalid diff content" }
    end

    pull_request = current_repository.pull_requests.open_pulls
      .where(
        head_repository_id: current_repository.id, # Ignore PRs from forks
        base_repository_id: current_repository.id,
        head_ref: Git::Ref.safe_ref_name(ref_names: branch.name)
      )
      # It shouldn't be possible to have multiple open PRs for the same branch,
      # but if there are we then let's just link to the most recent one
      .order(created_at: :desc)
      .first # domain-isolation-query-violation:ignore:packages/issues (SELECT)

    if create_draft_pr
      begin
        total_commits_count = proposed_commits_filter.accepted_commits.size + proposed_commits_filter.rejected_commits.size
        org = current_repository.owner
        pull_request_body = "This PR applies #{proposed_commits_filter.accepted_commits.size}/#{total_commits_count} suggestions from code quality [AI findings](#{repository_code_quality_recent_activity_url(org, current_repository)})."
        if proposed_commits_filter.rejected_commits.size > 0
          pull_request_body += " #{proposed_commits_filter.rejected_commits.size} #{'suggestion'.pluralize(proposed_commits_filter.rejected_commits.size)} #{'was'.pluralize(proposed_commits_filter.rejected_commits.size)} skipped to avoid creating conflicts."
        end

        pull_request ||= PullRequest.create_for!(current_repository, {
          user: current_user,
          base: current_repository.default_branch,
          head: branch.name,
          draft: true,
          title: "Potential #{"fix".pluralize(proposed_commits_filter.accepted_commits.size)} for #{proposed_commits_filter.accepted_commits.size} code quality #{"finding".pluralize(proposed_commits_filter.accepted_commits.size)}",
          body: "_#{pull_request_body}_",
        })
      rescue StandardError => err # rubocop:todo Lint/RescueException
        Failbot.report(err)
        return render status: 422, json: { message: "Something went wrong during PR creation" }
      end
    end

    analytics_event(
      category: "code_quality",
      action: "recent_activity_#{create_new_branch ? "create" : "update"}_branch",
      label: {
        fix_count: fixes.size,
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
      messages:,
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
