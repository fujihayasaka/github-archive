# typed: strict
# frozen_string_literal: true

# Helper class for extracting suggestion blocks from user PR review comments
# and converting them into GitHub::Diff::Entry objects compatible with the
# DiffEntrySuggestedChange commit path.
class ReviewComments::UserCommentSuggestion
  class Error < StandardError; end
  class ParseError < Error; end
  class InvalidIndexError < Error; end

  # Matches ```suggestion blocks in markdown. The opening fence can have
  # optional parameters (e.g. ```suggestion or ```suggestion\n).
  # The closing ``` is optional — an unclosed block captures to end-of-string.
  SUGGESTION_REGEX = T.let(/```\s?suggestion[^\n]*\n(.*?)(?:```|\z)/m, Regexp)

  NEWLINE_REGEXP = T.let(Regexp.union(["\r\n", "\r", "\n"]), Regexp)

  # Extract all ```suggestion blocks from a comment body as an array of strings.
  #
  # A similar regex exists in the Copilot SuggestionAcceptanceAnalyzer
  # (packages/copilot4prs/.../analyzer.rb) but it only extracts the *first*
  # match via `body.match`. We use `body.scan` here because a single comment
  # can contain multiple suggestion blocks and we need to address them by index.
  sig { params(body: String).returns(T::Array[String]) }
  def self.extract_all_suggestions(body)
    body.scan(SUGGESTION_REGEX).map { |match| match[0].to_s.sub(/\n\z/, "") }
  end

  sig { params(body: String, index: Integer).returns(String) }
  def self.extract_suggestion_at_index(body, index)
    suggestions = extract_all_suggestions(body)

    if suggestions.empty?
      raise ParseError.new("Comment body contains no suggestion blocks")
    end

    if index < 0 || index >= suggestions.length
      raise InvalidIndexError.new(
        "Suggestion index #{index} is out of bounds (comment has #{suggestions.length} suggestion(s))"
      )
    end

    T.must(suggestions[index])
  end

  # Build GitHub::Diff::Entry objects from a user comment's suggestion text
  # and the actual blob content at the PR head, matching the behavior of
  # PullRequestReviewComment::ApplySuggestedChange which reads original lines
  # from the blob rather than from the diff hunk stored on the thread.
  #
  # comment         - A PullRequestReviewComment with a suggestion in its body
  # suggestion_text - The extracted suggestion text for the selected block
  #
  # Returns an Array of GitHub::Diff::Entry
  sig do
    params(
      comment: T.untyped,
      suggestion_index: Integer,
    ).returns(T::Array[GitHub::Diff::Entry])
  end
  def self.build_diff_entries(comment:, suggestion_index:)
    suggestion_text = ReviewComments::UserCommentSuggestion.extract_suggestion_at_index(
      comment.body, suggestion_index
    )

    path = comment.path
    raise ParseError.new("Comment #{comment.id} has no file path") if path.blank?

    # An empty suggestion block means "delete these lines" — no additions.
    new_lines = suggestion_text.empty? ? [] : suggestion_text.split("\n", -1)

    # Determine the line range using current_line and start_position_offset,
    # matching PullRequestReviewComment::ApplySuggestedChange#replace_line.
    # current_line is a 0-indexed blob position; start_position_offset is
    # the number of additional lines above it that the comment spans.
    end_line = comment.current_line
    raise ParseError.new("Cannot determine current line for comment #{comment.id}") if end_line.nil?

    line_count = comment.start_position_offset || 0
    first_line = end_line - line_count

    # Read original lines from the blob at HEAD, matching the behavior of
    # ApplySuggestedChange which uses blob_at_path + content_lines[first_line..at].
    pr = comment.pull_request
    head_repo = pr&.head_repository
    raise ParseError.new("Head repository not found for comment #{comment.id}") if head_repo.nil?

    blob = head_repo.blob(pr.head_sha, path, { truncate: false, limit: 1.megabyte })
    raise ParseError.new("Blob not found for #{path} (comment #{comment.id})") if blob.blank?

    source_lines = blob.data.split(NEWLINE_REGEXP, -1)

    if first_line < 0 || first_line > end_line || end_line >= source_lines.length
      raise ParseError.new("Line range #{first_line}..#{end_line} is out of bounds for #{path} (#{source_lines.length} lines, comment #{comment.id})")
    end
    original_lines = source_lines[first_line..end_line] || []

    # first_line is 0-indexed; unified diff headers are 1-indexed
    start_line = first_line + 1

    diff_content = build_unified_diff(
      path: path,
      start_line: start_line,
      original_lines: original_lines,
      new_lines: new_lines
    )

    begin
      entries = []
      parser = GitHub::Diff::Parser.new(diff_content)
      parser.each do |entry|
        entries << entry
      end
      entries
    rescue GitHub::Diff::Parser::UnrecognizedText => err
      raise ParseError.new("Failed to parse generated diff for comment #{comment.id}: #{err.message}")
    end
  rescue ParseError, InvalidIndexError => e
    GitHub.logger.error("UserCommentSuggestion.build_diff_entries failed", "gh.pull_request.comment.id": comment.id, exception: e)
    raise
  end

  sig do
    params(
      path: String,
      start_line: Integer,
      original_lines: T::Array[String],
      new_lines: T::Array[String]
    ).returns(String)
  end
  def self.build_unified_diff(path:, start_line:, original_lines:, new_lines:)
    num_deletions = original_lines.length
    num_additions = new_lines.length

    lines = []
    lines << "diff --git a/#{path} b/#{path}"
    lines << "--- a/#{path}"
    lines << "+++ b/#{path}"
    lines << "@@ -#{start_line},#{num_deletions} +#{start_line},#{num_additions} @@"

    original_lines.each do |line|
      lines << "-#{line}"
    end

    new_lines.each do |line|
      lines << "+#{line}"
    end

    lines.join("\n") + "\n"
  end

  private_class_method :build_unified_diff
end
