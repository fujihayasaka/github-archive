# typed: true
# frozen_string_literal: true

class ConflictedFilesController < AbstractRepositoryController

  before_action :require_push_access

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql5,
    only: [:show]

  def show
    respond_to do |format|
      format.json do
        conflicted_file_contents_entry, ancestor_entry, base_entry, head_entry =
          this_pull.conflicted_file_contents(
            CGI.unescape(params[:name]).b,
            params[:ancestor_oid],
            params[:base_oid],
            params[:head_oid],
          )

        lang = head_entry.language || ancestor_entry.language || base_entry.language
        conflicted_file_mime_type = lang ? lang.codemirror_mime_type : nil

        render json: {
          conflicted_file: { data: conflicted_file_contents_entry.data, codemirror_mime_type: conflicted_file_mime_type },
          ancestor: { data: ancestor_entry.data, codemirror_mime_type: ancestor_entry.language ? ancestor_entry.language.codemirror_mime_type : nil },
          base: { data: base_entry.data, codemirror_mime_type: base_entry.language ? base_entry.language.codemirror_mime_type : nil },
          head: { data: head_entry.data, codemirror_mime_type: head_entry.language ? head_entry.language.codemirror_mime_type : nil },
        }
      end
    end
  end

  def resolve # rubocop:todo GitHub/UseRestfulActions
    file_params = params.to_unsafe_h[:files]
    return head(:bad_request) unless file_params.is_a?(Hash)

    cf = this_pull.conflicted_files
    if cf.nil?
      render json: { error: "someone pushed" }
      return
    end

    # we need the unescaped path to preserve line endings, but need to pass
    # the escaped path up through the job to avoid it being mangled by
    # background job serialization
    resolve_conflicts = {}
    cf.each do |file|
      path = CGI.escape(file)
      contents = file_params[path]
      resolve_conflicts[path] = this_pull.repository.preserve_line_endings(params[:pr_head_sha], file, contents) if contents
    end

    new_head_ref = nil
    if params[:commit_choice] == "quick-pull"
      new_head_ref = params[:target_branch]
    end

    result = PullRequests::ResolveMergeConflicts.execute(
      pull_request: this_pull,
      user: current_user,
      base_oid: params[:pr_base_sha],
      expected_head_oid: params[:pr_head_sha],
      resolve_conflicts: resolve_conflicts,
      new_head_ref: new_head_ref
    )

    case result
    when PullRequests::ResolveMergeConflicts::Success
      render json: { orchestration: { url: pull_request_orchestration_status_url(orchestration_id: result.orchestration.id) } }
    when PullRequests::ResolveMergeConflicts::Error
      render json: { error_message: result.error_message }, status: :unprocessable_entity
    else
      T.absurd(result)
    end
  end

  private

  memoize def this_pull
    PullRequest.with_number_and_repo(params[:id].to_i, current_repository)
  end

  def require_push_access
    render_404 unless this_pull && this_pull.head_repository &&
      this_pull.head_repository.pushable_by?(current_user, ref: this_pull.head_ref_name)
  end

  def route_supports_advisory_workspaces?
    true
  end
end
