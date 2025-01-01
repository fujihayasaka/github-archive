# typed: true
# frozen_string_literal: true

class WorkspaceEditor::SuggestionsController < WorkspaceEditor::ControllerBase

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Spokes

  DEFAULT_SOURCE_TYPE = "pull_request_review_comment"

  # List level data returned from index
  class TaskDisplayDataForComment
    attr_reader :source_id

    sig do params(
      comment: PullRequestReviewComment,
      outdated: T::Boolean,
      source_id: Integer,
      type: String,
    ).void
    end
    def initialize(comment:, outdated:, source_id:, type:)
      @comment = comment
      @outdated = outdated
      @source_id = source_id
      @type = type
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def to_h
      {
        outdated: @outdated,
        sourceId: @source_id,
        type: @type,
        **comment_info_for(@comment),
      }
    end

    private

    # comment left untyped because sorbet can't find it's dynamically defined method
    sig { params(comment: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
    def comment_info_for(comment)
      {
        author: author_info_for(comment),
        lineNumber: WorkspaceEditor::SuggestionsController.end_line_for_comment(comment),
        path: comment.path,
        startLineNumber: WorkspaceEditor::SuggestionsController.start_line_for_comment(comment),
      }
    end

    def author_info_for(comment)
      {
        avatarUrl: comment.user&.primary_avatar_url(24),
        displayLogin: comment.user&.display_login,
      }
    end
  end

  # Single suggestion "fully-hydrated" view of the data to return
  # Superset of the list data
  class TaskSuggestionsForComment < TaskDisplayDataForComment
    sig do params(
      comment: PullRequestReviewComment,
      html: String,
      outdated: T::Boolean,
      source_id: Integer,
      suggestions: T::Array[T.any(TaskSuggestionRawDiff, TaskSuggestionParsedDiff)],
      type: String,
      source_type: String,
      previous_comments: T.nilable(T::Array[PullRequestReviewComment]),
      following_comments: T.nilable(T::Array[PullRequestReviewComment]),
    ).void
    end
    def initialize(comment:, html:, outdated:, source_id:, suggestions:, type:, source_type: DEFAULT_SOURCE_TYPE, previous_comments: nil, following_comments: nil)
      super(comment: comment, outdated: outdated, source_id: source_id, type: type)

      @comment = comment
      @html = html
      @suggestions = suggestions
      @source_type = source_type
      @previous_comments = previous_comments
      @following_comments = following_comments
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def to_h
      result = super.to_h.merge({
        html: @html,
        sourceType: @source_type,
        suggestions: @suggestions.map(&:to_h),
      })

      result[:previousComments] = @previous_comments.map { |c| context_info_for(c) } unless @previous_comments.nil?
      result[:followingComments] = @following_comments.map { |c| context_info_for(c) } unless @following_comments.nil?

      result
    end

    def context_info_for(comment)
      {
        author: author_info_for(comment),
        id: comment.id,
        html: GitHub::Goomba::MarkdownPipeline.to_html(comment.body, { subject: comment }, nil),
      }
    end
  end

  class TaskSuggestionRawDiff
    sig { params(file_path: String, diff: String).void }
    def initialize(file_path:, diff:)
      @file_path = file_path
      @diff = diff
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def to_h
      {
        filePath: @file_path,
        diff: @diff,
      }
    end
  end

  class TaskSuggestionParsedDiff
    sig do params(
        file_path: String,
        old_start: Integer,
        old_lines: Integer,
        new_start: Integer,
        new_lines: Integer,
        lines: T::Array[String],
      ).void
    end
    def initialize(file_path:, old_start:, old_lines:, new_start:, new_lines:, lines:)
      @file_path = file_path
      @old_start = old_start
      @old_lines = old_lines
      @new_start = new_start
      @new_lines = new_lines
      @lines = lines
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def to_h
      {
        filePath: @file_path,
        diff: {
          oldStart: @old_start,
          oldLines: @old_lines,
          newStart: @new_start,
          newLines: @new_lines,
          lines: @lines
        }
      }
    end
  end

  def index
    respond_to do |format|
      all_suggestions = suggestion_display_data_from_review_comments + suggestion_display_data_from_ghas_comments
      if user_feature_enabled?(:hadron_comment_fix_generation)
        all_suggestions += thread_display_data_from_comments
      end

      all_suggestions.compact!
      all_suggestions = all_suggestions.uniq { |sug| sug.source_id }
      headers["X-Head-Sha"] = pull.head_sha

      response_map = all_suggestions.each_with_object({}) do |suggestion, hash|
        hash[suggestion.source_id] = suggestion.to_h
      end

      format.json do
        render json: response_map
      end
    end
  end

  def show
    suggestion = suggestion_from_comment
    headers["X-Head-Sha"] = pull.head_sha

    respond_to do |format|
      format.json do
        if suggestion
          render json: suggestion.to_h
        else
          render_404
        end
      end
    end
  end

  # start_line_number is only there if the comment targets multiple lines.
  # line will always be there, and is the end for multi-line targets.
  #
  # These are only present if the comment is NOT outdated.
  #
  # original_* are always present (but not necessarily the current position)
  # and should only be used with outdated comments where no other option exists.
  def self.start_line_for_comment(comment)
    comment.start_line_number || comment.line || comment.original_start_line || comment.original_line
  end

  def self.end_line_for_comment(comment)
    comment.line || comment.original_line
  end

  private

  def suggestion_display_data_from_review_comments
    comments = pull_comments.where("body like ?", "%```suggestion%")

    comments.filter_map { |comment| display_task_from_comment(comment, comment.outdated?, "suggestion") if suggestion?(comment) }
  end

  def suggestion_display_data_from_ghas_comments
    code_scanning_comments = pull.code_scanning_review_comments
      .preload(pull_request_review_comment: [:pull_request_review_thread, :user])

    # Required for the use of the component to work properly for HTML render
    # Given that, we'll just lean on the PR objects rather than making our own
    # service calls to gather the fixes.
    CodeScanning::ReviewCommentComponent.preload_review_comments(pull_request: pull) if code_scanning_comments.any?

    code_scanning_comments.filter_map do |code_scanning_comment|
      suggested_fix = ghas_suggested_fix(code_scanning_comment)
      next unless suggested_fix

      pr_comment = code_scanning_comment.pull_request_review_comment
      outdated = pr_comment.outdated? || suggested_fix.outdated
      display_task_from_comment(pr_comment, outdated, "autofix")
    end
  end

  def thread_display_data_from_comments
    first_comments = pull_comments
      .map { |comment| comment.pull_request_review_thread }
      .uniq(&:id)
      .filter_map do |thread|
        display_task_from_comment(thread.comments.first, false, "generative") if !comment_is_ghas_autofix?(thread.comments.first) && !thread.outdated?
      end
  end

  def suggestion_from_comment
    pull_request_review_comment = pull.review_comments.find(params[:pull_request_review_comment_id])

    if pull_request_review_comment.pull_request_review.variant_type == "code_scanning"
      CodeScanning::ReviewCommentComponent.preload_review_comments(pull_request: pull)
      code_scanning_comment = pull.code_scanning_review_comment_for_comment(pull_request_review_comment.id)
      suggestion_from_code_scanning_comment(code_scanning_comment)
    else
      suggestion = suggestion_from_review_comment(pull_request_review_comment)
      if suggestion.nil? && user_feature_enabled?(:hadron_comment_fix_generation)
        generative_suggestion_from_comment(pull_request_review_comment)
      else
        suggestion
      end
    end
  end

  def suggestion_from_review_comment(comment)
    return nil unless ok_to_suggest?(comment)

    # Note can't use typical to_text, have to get intermediate raw version(s)
    suggestions = GitHub::Goomba::PRCommentSuggestionPipeline.call(comment.body)[:raw_suggestions]
    return unless suggestions.present?

    # Use helpers because lines on the comment are... complicated
    # See the methods for more info
    start_line = self.class.start_line_for_comment(comment)
    end_line = self.class.end_line_for_comment(comment)

    original_lines = original_lines_from_diff_hunk(start_line, end_line, comment)

    diffs = suggestions.map do |suggestion|
      suggestion_lines = suggestion
        .split(DiffEntrySuggestedChange::NEWLINE_REGEXP, -1)
        .map do |line|
          "+#{line}"
        end

      TaskSuggestionParsedDiff.new(
        file_path: comment.path,
        old_start: start_line,
        old_lines: original_lines.count,
        new_start: start_line,
        new_lines: suggestion_lines.count,
        lines: original_lines + suggestion_lines
      )
    end

    context = {
      diff_component: Suggestions::SuggestedChangesDiffComponent,
      diff_component_view_context: EmptyController.new.view_context,
      start_line_number: start_line,
      subject: comment
    }

    html = GitHub::Goomba::MarkdownPipeline.to_html(comment.body, context, nil)

    thread = comment.pull_request_review_thread
    previous_comments = thread&.comments.select { |c| c.id != comment.id && c.created_at < comment.created_at }
    following_comments = thread&.comments.select { |c| c.id != comment.id && c.created_at >= comment.created_at }


    TaskSuggestionsForComment.new(
      comment:,
      html:,
      outdated: comment.outdated?,
      source_id: comment.id,
      suggestions: diffs,
      type: "suggestion",
      previous_comments: previous_comments || [],
      following_comments: following_comments || []
    )
  end

  def suggestion_from_code_scanning_comment(code_scanning_comment)
    pull_request_review_comment = code_scanning_comment.pull_request_review_comment
    suggested_fix = ghas_suggested_fix(code_scanning_comment)
    return if suggested_fix.nil?

    outdated = pull_request_review_comment.outdated? || suggested_fix.outdated

    special_context = view_context.dup
    special_context.formats = [:html]
    html = CodeScanning::ReviewCommentComponent.new(
      autofix_header_type: :apply_button,
      pull_request: pull,
      pull_request_review_comment:,
      skip_interactive_elements: true,
      skip_view_patch_menu_item: true).render_in(special_context)

    TaskSuggestionsForComment.new(
      comment: pull_request_review_comment,
      html:,
      outdated:,
      source_id: pull_request_review_comment.id,
      suggestions: suggested_fix.files.map do |file|
        TaskSuggestionRawDiff.new(
          file_path: file.file_path,
          diff: file.diff_content)
      end,
      type: "autofix"
    )
  end

  def generative_suggestion_from_comment(comment)
    thread = comment.pull_request_review_thread

    return nil if thread.outdated?

    comments = thread.comments.map do |comment|
      {
        author: {
          displayLogin: comment.user.display_login,
          avatarUrl: comment.user.primary_avatar_url(24),
        },
        body: comment.body_html,
        bodyText: comment.body,
        commitOid: comment.commit_id,
        createdAt: comment.created_at,
        updatedAt: comment.updated_at,
        diffHunk: comment.diff_hunk,
        id: comment.id,
        inReplyToId: comment.in_reply_to&.id,
        lineNumber: WorkspaceEditor::SuggestionsController.end_line_for_comment(comment),
        originalCommitOid: comment.original_commit_id,
        originalLineNumber: comment.original_line,
        originalStartLineNumber: comment.original_start_line,
        pullRequestId: comment.pull_request_id,
        path: comment.path,
        side: comment.side,
        startLineNumber: WorkspaceEditor::SuggestionsController.start_line_for_comment(comment),
        startSide: comment.start_side,
        subjectType: comment.subject_type,
        type: "generative",
      }
    end

    first_comment = comments.shift

    {
      author: {
        displayLogin: comment.user.display_login,
        avatarUrl: comment.user.primary_avatar_url(24),
      },
      comment: first_comment,
      html: "",
      lineNumber: WorkspaceEditor::SuggestionsController.end_line_for_comment(comment),
      outdated: comment.outdated?,
      path: comment.path,
      replies: comments,
      sourceId: comment.id,
      sourceType: "pull_request_review_comment",
      startLineNumber: WorkspaceEditor::SuggestionsController.start_line_for_comment(comment),
      suggestions: [],
      type: "generative"
    }
  end

  def suggestion?(comment)
    suggestions = GitHub::Goomba::PRCommentSuggestionPipeline.call(comment.body)[:raw_suggestions]
    suggestions.present?
  end

  def display_task_from_comment(comment, outdated, type)
    return nil unless ok_to_suggest?(comment)

    TaskDisplayDataForComment.new(
      comment:,
      outdated: outdated,   # Don't just use comment.outdated? as GHAS adds to outdated logic
      source_id: comment.id,
      type:
    )
  end

  memoize def pull_comments
    pull
      .review_comments
      .preload(:user, :pull_request_review_thread, :pull_request_review)
  end

  def ok_to_suggest?(comment)
    thread = comment.pull_request_review_thread
    !!(thread && !thread.resolved?)
  end

  def original_lines_from_diff_hunk(start_line, end_line, comment)
    desired_line_count = end_line - start_line + 1
    comment.diff_hunk
      .split("\n")[-desired_line_count..]
      .map do |line|
        line[0] = "-"
        line
      end
  end

  def comment_is_ghas_autofix?(comment)
    comment.pull_request_review.variant_type == "code_scanning"
  end

  def ghas_suggested_fix(code_scanning_comment)
    pull_request_review_comment = code_scanning_comment.pull_request_review_comment
    return nil unless ok_to_suggest?(pull_request_review_comment)

    # Expects that we've already preloaded fixes and alerts. If we ever revert
    # the render on list loading, we may want to revert this to calling for
    # fixes directly as we don't need the full load for just the diffs, but do
    # for HTML UI.

    # Fine for alert to be nil (mostly for local). If things are really missing
    # we shouldn't find fixes either and will bounce...
    alert = pull.code_scanning_alert_for_review_comment(pull_request_review_comment)
    resolution = alert&.result&.resolution
    return if resolution && resolution != :NO_RESOLUTION

    suggested_fix_alert = pull.code_scanning_suggested_fix_alert(code_scanning_comment.alert_number)
    suggested_fix_alert&.suggested_fix
  end
end
