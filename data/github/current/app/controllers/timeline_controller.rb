# typed: true
# frozen_string_literal: true

class TimelineController < AbstractRepositoryController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Permissions,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    only: [:timeline_focused_item]

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Copilot,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Notify,
    ApplicationRecord::RepositoriesActionsChecks,
    optional: true, only: [:timeline_focused_item]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Spokes,
    ApplicationRecord::IamAbilities,
    only: [:show]

  def show
    return render_404 unless anchor_global_ids[:timeline]

    # TimelineController#show should be equivalent to #timeline_focused_item - however we still have legacy API usages
    # Which can route through here, and therefore we can't remove this endpoint yet.
    # We also need to convert the legacy param naming to the new one for the cursors.
    begin
      params[:before_cursor] = params.dig(:variables, :before).presence
      params[:after_cursor] = params.dig(:variables, :after).presence
    rescue TypeError
      head :bad_request and return
    end

    timeline_focused_item
  end

  def timeline_focused_item # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless object
    return render_404 unless anchor_global_ids[:timeline]

    if object.is_a?(Issue)
      timeline_owner = Issue::ShowLoader.issue_node(
        object,
        current_repository,
        current_user,
        cap_filter: cap_filter,
        pagination_params: { per_page: 1, before_cursor: params[:before_cursor], after_cursor: params[:after_cursor], focused_item_global_id: anchor_global_ids[:timeline] }
      )

      render Issues::PagedTimelineComponent.new(timeline_owner: timeline_owner), layout: false
    elsif object.is_a?(PullRequest)
      timeline_owner = PullRequest::ShowLoader.issue_node(
        object,
        current_repository,
        current_user,
        cap_filter: cap_filter,
        pagination_params: { per_page: 1, before_cursor: params[:before_cursor], after_cursor: params[:after_cursor], focused_item_global_id: anchor_global_ids[:timeline] }
      )

      render PullRequests::PagedTimelineComponent.new(timeline_owner: timeline_owner), layout: false
    else
      render_404
    end
  rescue Platform::Errors::Cursor
    render_404
  end

  private

  memoize def object
    possible_types = [
      Platform::Objects::Issue,
      Platform::Objects::PullRequest,
    ]
    typed_object_from_id(possible_types, params[:id])
  rescue Platform::Errors::NotFound
    nil
  end

  ANCHOR_REGEXPS = [
    /\A(commitcomment)-(\d+)\z/, # comment left on a PR commit from outside PR context
    /\A(commits-pushed)-([0-9a-f]{7})\z/, # "hubot added some commits 19 days ago"
    /\A(pullrequestreview)-(\d+)\z/, # review
    /\A(discussion)_r(\d+)\z/, # individual comment in a review comment thread
    /\A(discussion-diff)-(\d+)(?:[LR]-?\d+)?\z/, # "hubot commented on the diff 19 days ago"
    /\A(diff-for-comment)-(\d+)\z/, # "hubot commented on the diff 19 days ago"
    /\A(event)-(\d+)\z/, # miscellaneous timeline event
    /\A(issuecomment)-(\d+)\z/, # comment left directly on PR/issue
    /\A(ref-commit)-([0-9a-f]{7})\z/, # reference from a commit
    /\A(ref-issue)-(\d+)\z/, # reference from an issue
    /\A(ref-pullrequest)-(\d+)\z/, # reference from a PR
  ]

  memoize def anchor_global_ids
    match = ANCHOR_REGEXPS.each do |regexp|
      this_match = regexp.match(params[:anchor])
      break this_match if this_match
    end

    anchor_type, id = match[1], match[2]
    map_anchor_to_focus_global_ids(anchor_type, id)
  end

  def map_anchor_to_focus_global_ids(anchor_type, id)
    timeline_global_id = review_thread_global_id = review_comment_global_id = nil

    case anchor_type

    when "commitcomment"
      comment = CommitComment.find(id)
      commit_comment_thread = Platform::Models::PullRequestCommitCommentThread.new(
        object, comment.repository_id, comment.commit_id, comment.path, comment.position
      )
      timeline_global_id = commit_comment_thread.global_relay_id

    when "commits-pushed"
      commit_oid = object.repository.ref_to_sha(id)
      commit = object.repository.commits.find(commit_oid)
      timeline_global_id = Platform::Models::PullRequestCommit.new(object, commit).global_relay_id

    when "pullrequestreview"
      timeline_global_id = PullRequestReview.find(id).global_relay_id

    when "discussion-diff", "diff-for-comment"
      comment = PullRequestReviewComment.find(id)

      timeline_global_id = comment.pull_request_review_thread&.global_relay_id
      review_comment_global_id = comment.global_relay_id

    when "discussion"
      comment = PullRequestReviewComment.find(id)

      if comment.pull_request_review_thread&.legacy?
        timeline_global_id = comment.pull_request_review_thread&.global_relay_id
        review_comment_global_id = comment.global_relay_id
      else
        timeline_global_id = comment.pull_request_review_thread&.pull_request_review&.global_relay_id
        review_thread_global_id = comment.pull_request_review_thread&.global_relay_id
        review_comment_global_id = comment.global_relay_id
      end

    when "issuecomment"
      timeline_global_id = IssueComment.find(id).global_relay_id

    when "event"
      timeline_global_id = IssueEvent.find(id).global_relay_id

    when "ref-commit"
      commit_oid = object.repository.ref_to_sha(id)
      event = IssueEvent.where(issue_id: issue_id, commit_id: commit_oid).first
      timeline_global_id = event&.global_relay_id

    when "ref-issue", "ref-pullrequest"
      cross_reference = CrossReference.where(target_id: issue_id, source_id: id).first
      timeline_global_id = cross_reference&.global_relay_id
    end

    {
      timeline: timeline_global_id,
      review_thread: review_thread_global_id,
      review_comment: review_comment_global_id,
    }
  rescue ActiveRecord::RecordNotFound
    {}
  end

  memoize def issue_id
    object.is_a?(PullRequest) ? object.issue.id : object.id
  end
end
