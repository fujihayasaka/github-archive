# typed: false
# frozen_string_literal: true

module DiffHelper
  DOTFILE_REGEX = %r{\A[.]}
  DIFF_FILE_LABEL_TRUNCATION_LENGTH = 92
  TOGGLEABLE_LENGTH = 10
  REVIEW_DISMISSED_LENGTH = 15

  include GitHub::UTF8
  include EscapeHelper
  extend ActionView::Helpers::TagHelper
  extend EscapeHelper
  include DiffLineChangeMarker

  # Determine if the diff should be soft-wrapped based on the filename.
  #
  # path - a filename with the extension
  def soft_wrap?(path)
    languages = Linguist::Language.find_by_filename(path)
    languages = Linguist::Language.find_by_extension(path) if languages.empty?

    languages.any? { |lang| lang.wrap }
  end

  def diff_file_type(diff)
    return "Binary" if diff.binary?
    "Empty" if diff.changes == 0 && !diff.renamed?
  end

  def diff_label(diff)
    return "BIN" if diff.binary?
    "0" if diff.changes == 0
  end

  def format_diffstat_line(diff, total)
    format_diffstat_line_from(total: total, changes: diff.changes, additions: diff.additions,
                              deletions: diff.deletions)
  end
  module_function :format_diffstat_line

  def format_diffstat_line_from(total:, changes:, additions:, deletions:)
    stat_line = diffstat_line_from(columns: total, changes: changes, additions: additions,
                                   deletions: deletions)

    adjusted_additions = stat_line.count("+")
    adjusted_deletions = stat_line.count("-")
    padding = total - (adjusted_additions + adjusted_deletions)

    tags = []
    tags += [content_tag(:span, "", class: "diffstat-block-added")] * adjusted_additions
    tags += [content_tag(:span, "", class: "diffstat-block-deleted")] * adjusted_deletions
    tags += [content_tag(:span, "", class: "diffstat-block-neutral")] * padding
    safe_join(tags)
  end
  module_function :format_diffstat_line_from

  def diffstat_line_from(changes:, additions:, deletions:, columns: 80, addition_symbol: "+",
                         deletion_symbol: "-")
    adjust = changes > columns ? columns / changes.to_f : 1.0

    (addition_symbol * (additions * adjust)) + (deletion_symbol * (deletions * adjust))
  end
  module_function :diffstat_line_from

  def code_marker_for(line_type)
    case line_type
    when :addition
      "+"
    when :deletion
      "-"
    else
      " "
    end
  end

  def diff_file_label(diff, truncate = true, toggleable: false, review_dismissed: false)
    if diff.copied? || diff.renamed?
      a_path, b_path = diff.a_path, diff.b_path
      original_path = truncate ? reverse_truncate(a_path, length: 44) : a_path
      new_name = truncate ? reverse_truncate(b_path, length: 44) : b_path
      safe_join([original_path, "→", new_name], " ")
    else
      path = diff.path || diff.a_path
      length = DIFF_FILE_LABEL_TRUNCATION_LENGTH
      length -= TOGGLEABLE_LENGTH if toggleable
      length -= REVIEW_DISMISSED_LENGTH if review_dismissed
      truncate ? reverse_truncate(path, length: length) : path
    end
  end

  def reverse_truncate(text, options = {})
    escape = options.fetch(:escape) { true }
    # Never escape inside truncate, as return value is reversed
    options = options.merge(escape: false)

    result = truncate(text.reverse, options).reverse
    escape ? h(result) : result
  end

  def head_repository
    if @comparison && @comparison.head_repo
      @comparison.head_repo
    else
      current_repository
    end
  end

  def base_repository
    if @comparison && @comparison.base_repo
      @comparison.base_repo
    else
      current_repository
    end
  end

  def diff_base_blob(diff, repository = nil)
    TreeEntry.new(repository || head_repository, {
      "oid" => diff.a_blob,
      "path" => diff.a_path,
      "mode" => diff.a_mode,
      "type" => "blob",
    })
  end

  def diff_head_blob(diff, repository = nil)
    TreeEntry.new(repository || head_repository, {
      "oid" => diff.b_blob,
      "path" => diff.b_path,
      "mode" => diff.b_mode,
      "type" => "blob",
    })
  end

  def diff_blob(diff, repository = nil)
    if diff.deleted?
      diff_base_blob(diff, repository)
    else
      diff_head_blob(diff, repository)
    end
  end

  # The path to view the raw head blob in the same domain (no redirect to raw.)
  def diff_head_blob_url(diff)
    "/#{head_repository.name_with_display_owner}/raw/#{diff.b_sha}/#{escape_url_branch(diff.b_path)}"
  end

  # The path to view the raw base blob in the same domain (no redirect to raw.)
  def diff_base_blob_url(diff)
    "/#{base_repository.name_with_display_owner}/raw/#{diff.a_sha}/#{escape_url_branch(diff.a_path)}"
  end

  def diff_head_tree_url(diff)
    "/#{head_repository.name_with_display_owner}/tree/#{diff.b_sha}/#{escape_url_branch(diff.b_path)}"
  end

  def diff_base_tree_url(diff)
    "/#{head_repository.name_with_display_owner}/tree/#{diff.a_sha}/#{escape_url_branch(diff.a_path)}"
  end

  def diff_blob_excerpt_url(sha, path, mode, params = {})
    pull_request_context = params.delete(:pull_request_context)
    query_params = params.dup
    query_params[:path] = path
    query_params[:mode] = mode
    query_params[:diff] = params[:diff] if params[:diff]
    query_params[:context] = "pull_request" if pull_request_context
    query_params[:pull_request_id] = pull_request_context if pull_request_context
    "/#{base_repository.name_with_display_owner}/blob_excerpt/#{sha}?#{query_params.to_query}"
  end

  def diff_blob_expand_url(sha, path, mode, params = {})
    pull_request_context = params.delete(:pull_request_context)
    query_params = params.dup
    query_params[:path] = path
    query_params[:mode] = mode
    query_params[:diff] = params[:diff] if params[:diff]
    query_params[:context] = "pull_request" if pull_request_context
    query_params[:pull_request_id] = pull_request_context if pull_request_context
    "/#{base_repository.name_with_display_owner}/blob_expand/#{sha}?#{query_params.to_query}"
  end

  # The path to view the blob page at a specific SHA
  def diff_blob_path(diff, params = {})
    sha = diff.deleted? ? diff.a_sha : diff.b_sha
    file_path = diff.deleted? ? diff.a_path : diff.b_path
    path = "/#{base_repository.name_with_display_owner}/blob/#{sha}/#{escape_url_branch(file_path)}"

    if params.empty?
      path
    else
      "#{path}?#{params.to_query}"
    end
  end

  # The path to view the blob page on the branch of the current comparison. If
  # the comparison's head is a SHA1, this falls back to diff_blob_path.
  #
  # diff   - The GitHub::Diff::Entry identifying the blob to link to.
  # action - Either :view or :edit.
  # params - A object containing any URL parameters
  #
  # Returns the URL encoded path to the blob page for the diff entry.
  def diff_blob_branch_path(diff, action = :view, params = {})
    action = :blob if action.nil? || action == :view
    if !diff.deleted? && @pull && @pull.head_ref_exist?
      path = "/#{head_repository.name_with_display_owner}/#{action}/#{escape_url_branch(@pull.head_ref_name)}/#{escape_url_branch(diff.b_path)}"

      if !params.empty?
        path += "?#{params.to_query}"
      end

      path
    else
      diff_blob_path(diff, params)
    end
  end

  # Get the "type" of this diff if it's not usable in the online editor.
  # Used to fill in the following madlibs in diff/_diff.html.erb:
  #
  #   Online editor is disabled for {type} files.
  #
  # Returns a string "type" name, or nil if the blob this diff describes is
  # editable.
  def diff_uneditable_type(diff)
    if diff.binary?
      "binary"
    elsif diff.lfs_pointer?
      "Git LFS"
    end
  end

  # the copilot diff chat react partial (ui/packages/copilot-code-chat) should be disabled in certain situations
  def disable_copilot_diff_entry?(entry, repository)
    repository.nil? || entry.path.blank? || entry.deleted? || entry.binary? || entry.submodule? || entry.lfs_pointer?
  end

  # Can the current user edit blobs for the current pull request? Must be logged
  # in and under an open pull request's context. Edit controls are only shown
  # for users that have push access to the pull request's head repository.
  #
  # This has some kinks. PRs sent from forks are only editable by the fork's
  # owner or collaborators which does not include the owner of the repository
  # the PR is submitted on by default. Hoping we can eventually make this more
  # open at some point.
  #
  # Returns true when the current user can edit the PR's blobs, falsey otherwise.
  def can_edit_pull_request_blobs?
    return @can_edit_pull_request_blobs if defined?(@can_edit_pull_request_blobs)
    @can_edit_pull_request_blobs = can_edit_pull_request_blobs_check
  end

  # Perform the current user can edit blobs check for the current pull request.
  # This is an expensive operation.
  def can_edit_pull_request_blobs_check
    logged_in? &&
    @pull && !@pull.closed? && @pull.head_ref_exist? &&
    @pull.head_ref_pushable_by?(current_user)
  end

  def diff_short_path(diff)
    path = diff.try(:path) || diff.a_path || diff.b_path
    Digest::SHA256.hexdigest(path)[0, 7]
  end

  # Abbreviates two paths like 'git diff --stat'
  #   >> abbreviate_rename 'foo/bar/baz.txt', 'foo/bling/baz.txt'
  #   => "foo/{bar => bling}/baz.txt
  def abbreviate_rename(from, to, arrow = "=>")
    from, to = from.split("/"), to.split("/")

    front = []
    while from.first && from.first == to.first
      from.shift
      front << to.shift
    end

    back = []
    while from.last && from.last == to.last
      from.pop
      back.unshift to.pop
    end

    from, to = from.join("/"), to.join("/")
    if front.empty? && back.empty?
      [from, arrow, to].join
    else
      (front + ["{#{from}#{arrow}#{to}}"] + back).join("/")
    end
  end

  def diff_toc_label(diff, length: 100)
    if diff.copied? || diff.renamed?
      path = abbreviate_rename(diff.a_path, diff.b_path, " → ")
      reverse_truncate(path, length: length)
    else
      reverse_truncate(diff.path, length: length)
    end
  end

  def diff_toc_basename(diff, length: 100)
    if diff.copied? || diff.renamed?
      path = abbreviate_rename(File.basename(diff.a_path), File.basename(diff.b_path), " → ")
      reverse_truncate(path, length: length)
    else
      reverse_truncate(File.basename(diff.path), length: length)
    end
  end

  def diff_mode_label(diff)
    a, b = diff.a_mode, diff.b_mode
    if a && b && a != b && a != GitHub::NULL_MODE && b != GitHub::NULL_MODE
      safe_join([diff.a_mode, "→", diff.b_mode], " ")
    end
  end

  # DOM id for a review comment.
  #
  # Note that for a PullRequestReviewComment, you **must** specify if it is
  # rendering in a diff comment_context or discussion comment_context.
  # NOTE: the discussion comment_context isn't actually a "diff" view, but
  # this method handles that anyways.
  #
  # Returns a String
  def diff_comment_id(comment, comment_context = "diff")
    case comment
    when CommitComment
      "commitcomment-#{comment.id}"
    when PullRequest
      "issue-#{comment.issue.id}"
    when PullRequestReview
      "#{comment.class.name.downcase}-#{comment.id}"
    when PullRequestReviewComment
      case comment_context.to_s
      when "discussion"
        "#{CommentsHelper::DISCUSSION_DOM_ID_PREFIX}#{comment.id}"
      when "diff"
        "#{CommentsHelper::COMMIT_COMMENT_DOM_ID_PREFIX}#{comment.id}"
      else
        "#{CommentsHelper::COMMIT_COMMENT_DOM_ID_PREFIX}#{comment.id}"
      end
    when GistComment
      comment.anchor
    else
      raise TypeError, "unknown comment type: #{comment.class}"
    end
  end

  # Detect next path after the current in a set of changes.
  #
  # change - Array of Hash changes
  # page   - Integer page number
  #
  # Returns
  def diff_previous_changed_path(changes, page)
    filenames = changes.map { |c| c["old_file"]["path"] }
    filenames[page - 2] if page > 1
  end

  # Detect next path after the current in a set of changes.
  #
  # change - Array of Hash changes
  # page   - Integer page number
  #
  # Returns
  def diff_next_changed_path(changes, page)
    filenames = changes.map { |c| c["old_file"]["path"] }
    filenames[page]
  end

  def get_file_type(path)
    return if path.blank?

    file_type = File.extname(path)
    return utf8(file_type) if file_type.present?

    basename = File.basename(path)
    dotfile = DOTFILE_REGEX.match(utf8(basename))
    return "dotfile" if dotfile

    "No extension"
  end
end
