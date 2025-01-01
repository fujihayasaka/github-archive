# typed: false
# frozen_string_literal: true

class CollaboratorPromptController < GitContentController
  MAX_COMMITS = 80
  depends_on_clusters ApplicationRecord::Mysql1, ApplicationRecord::Collab, ApplicationRecord::Configurations, ApplicationRecord::IssuesPullRequests, ApplicationRecord::Repositories, ApplicationRecord::Spokes

  before_action :require_feature_flag
  before_action :require_ref

  # Currently this endpoint will return both a constructed prompt and all of the
  # context it uses, in case we decide to assemble it downstream from this response instead,
  # such as in a CAPI agent or on the client side.
  def show
    authors = {} # Still sort of an N+1 issue but at least cache per-author
    commits = []

    # This is a crude filter that doesn't account for numerous repo access scenarios.
    # But it handles the obvious case of excluding former employees, esp for GH.
    filter_to_org_members = current_repository.owner&.organization? && current_repository.private?
    member_ids = current_repository.owner.member_ids if filter_to_org_members

    load_recent_non_merge_commits.each do |c|
      author = authors[c.author_email] ||= c.author

      next unless author&.id
      next if author.id == current_user.id
      next if filter_to_org_members && !member_ids.include?(author.id)

      commit = {
        author: author.display_login,
        author_avatar_url: author.primary_avatar_url,
        date: c.date,
        message: c.message,
      }

      commits << commit
    end

    result = { commits: }

    if current_issue
      result[:issue] = {
        title: current_issue.title,
        body: current_issue.body,
        author: {
          id: current_issue.user_id,
          avatar_url: current_issue.user.primary_avatar_url,
        },
        assignees: current_issue.assignees.map do |assignee|
          {
            id: assignee.id,
            avatar_url: assignee.primary_avatar_url,
          }
        end
      }
    end

    commit_prompt_clause = <<~PROMPT
      You will return a ranked list of relevant collaborators, each with a rank-tag.

      First, consider the commit history below:

      #{result[:commits].map do |c|
        [
          c[:author],
          c[:date].strftime("%Y-%m-%d %H:%M:%S"),
          c[:message],
        ].join("\n")
      end.join("\n\n")}

      Use the content of the commit messages to determine the relative impact of each commit in the history. Then consider the relative impact of commits by each user, as well as the total number of commits by each user, to rank the top #{MAX_COMMITS} collaborators in terms of impact. Prioritize change size and complexity over commit count unless commits are diverse in nature. If there are large gaps in time between commits, lend extra weight to recent ones. List the authors, their rank, their commit count, and 1-2 short sentences, explaining why they were ranked (1) above the next user and below the previous user.
      Assign the rank-tags of "High Impact Contributor", "Recent Contributor", "Frequent Contributor", or just "Contributor" to each entry in the rankings.
    PROMPT

    issue_prompt_clause = if current_issue # Have not tested this at all
      <<~PROMPT

        Next, consider the issue below:

        <issue>
          Title: #{result[:issue][:title]}
          Author: #{result[:issue][:author][:id]}
          Assignee(s): #{result[:issue][:assignees].none? ? 'None' : result[:issue][:assignees].map { |a| a[:id] }.join(", ")}
          Body: #{result[:issue][:body]}
        </issue>

        If any commit authors overlap with this issue's authors/assignees, weigh them moderately higher in the ranking, and reassign them with the rank-tag of "Aware Contributor".
        If any commit messages clearly share themes with the issue, or involve making changes similar to those called for in the issue, weigh the commit author slightly higher in the ranking, and reassign them with the rank-tag of "Similar Contributor".
        If any commit messages are obviously and directly related to the issue title or body, weigh the commit author substantially higher in the ranking, and reassign them with the rank-tag of "Domain Expert".
      PROMPT
    end

    result[:prompt] = <<~PROMPT
      #{commit_prompt_clause}#{issue_prompt_clause}
      Return up to the top 3 collaborators and their rank-tags in JSON format with no commentary or explanation:
      [{ "id": integer, "avatar_url": string, "username": string, "rank": string }, ...]
    PROMPT

    render json: result

  end

  private

  def current_commit
    if current_commit_oid
      path_prefix = ::Commit.extract_path_prefix_from_expression(current_path)
      Platform::Loaders::GitObject.load(current_repository, current_commit_oid, path_prefix:).sync
    end
  rescue GitRPC::ObjectMissing
    nil
  end

  def load_recent_non_merge_commits
    current_repository.paged_commits(current_commit_oid, 1, MAX_COMMITS, { path: current_path })
  rescue GitRPC::CommandFailed, GitRPC::Timeout, GitRPC::ObjectMissing, Platform::Errors::Cursor => e
    GitHub.logger.error(
      "exception.message": e.message,
      "code.namespace": "CollaboratorPromptController",
      "code.function": "load-recent-non-merge-commits",
      "gh.user.id": current_user.id
    )
    deliver_error! 500
  end

  def collaborator_prompt_params
    params.permit(:path, :ref, :issue, :user_id, :repository, :format)
  end

  memoize def current_commit_oid
    current_repository.ref_to_sha(collaborator_prompt_params[:ref])
  end

  memoize def current_issue
    if collaborator_prompt_params[:issue]
      current_repository.issues.find_by_number(collaborator_prompt_params[:issue]) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end
  end

  memoize def current_path
    if collaborator_prompt_params[:format]
      "#{collaborator_prompt_params[:path]}.#{collaborator_prompt_params[:format]}"
    else
      collaborator_prompt_params[:path]
    end
  end

  def try_to_expand_path
  end

  def require_ref
    render_404 unless current_commit_oid
  end

  def require_feature_flag
    render_404 unless current_user.feature_flag_enabled?(:copilot_metadata_poc, default: false)
  end
end
