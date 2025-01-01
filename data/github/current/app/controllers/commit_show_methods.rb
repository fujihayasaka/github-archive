# typed: false
# frozen_string_literal: true

# Used to avoid logic duplication between CommitController and voltron CommitFragmentsController
module CommitShowMethods
  COMMENTS_PER_PAGE = TimelineHelper::DEFAULT_PAGE_SIZE

  def fetch_page(comments, before_comment_id = nil, until_comment_id = nil)
    if until_comment_id
      total_comments_size = comments.size
      until_comments = comments.where("commit_comments.id >= ?", until_comment_id)
      # If we are larger than the page size or we have all the comments, we can return the comments
      if until_comments.size >= COMMENTS_PER_PAGE || until_comments.size == total_comments_size
        current_commit.can_load_more_comments = until_comments.size < total_comments_size
        return until_comments
      end
    end

    if before_comment_id
      comments = comments.where("commit_comments.id < ?", before_comment_id)
    end

    page = comments.last(COMMENTS_PER_PAGE + 1)
    has_more = page.size > COMMENTS_PER_PAGE
    current_commit.can_load_more_comments = has_more
    page.shift if has_more
    page
  end

  def file_list_view
    return nil if params[:toc]
    @file_list_view ||= Diff::FileListView.new(
      commit: current_commit,
      diffs: current_commit.diff,
      params: params,
      current_user: current_user,
      commentable: view_context.issue_thread_commentable?,
      progressive: true,
    )
  end

  def preload_commit_comment_data(until_comment_id = nil)
    comments = CommitComment.for_display(current_user, current_commit, current_repository)
    last_discussion_comments = fetch_page(comments.discussion, nil, until_comment_id)
    file_list_view_comments = file_list_view&.threads&.flat_map(&:comments) || []

    preload_commit_comment_associations(last_discussion_comments + file_list_view_comments)

    current_commit.comments = last_discussion_comments
    current_commit.comment_count = comments.discussion.count
  end

  def preload_discussion_comments_data(before_comment_id = nil)
    comments = CommitComment.for_display(current_user, current_commit, current_repository)
    last_discussion_comments = fetch_page(comments.discussion, before_comment_id)
    preload_commit_comment_associations(last_discussion_comments)

    current_commit.comments = last_discussion_comments
    current_commit.comment_count = comments.discussion.count
  end

  def preload_commit_comment_associations(comments)
    GitHub::PrefillAssociations.prefill_associations(comments, [:user, :repository], available_records: [current_user, current_repository])
    GitHub::PrefillAssociations.prefill_batch_method(comments, :prelude_user_logins_by_reaction)

    Promise.all(comments.map { |comment| [comment.async_viewer_can_read_user_content_edits?(current_user), comment.async_latest_user_content_edit] }.flatten).sync
    Promise.all(
        comments.map { |comment| CommentAuthorAssociation.new(comment: comment, viewer: current_user).async_to_sym.then { |sym| comment.preload_attr(:author_association_symbol, sym) } }
      ).sync
  end
end
