# typed: true
# frozen_string_literal: true

require "scientist"

# This class was deprecated in favor of a database-backed
# pull request review thread model that will be introduced
# in the future.
#
# See #79020 and #79074 for more information.
class DeprecatedPullRequestReviewThread
  attr_accessor :activerecord_pull_review_thread, :start_side

  include GitHub::Relay::GlobalIdentification
  include GitHub::Memoizer

  # Experiment for better threads
  extend Scientist

  # Create a new `DeprecatedPullRequestReviewThread`.
  #
  # pull - optional `PullRequest` that this thread is a part of
  # pull_comparison - `PullRequest::Comparison`
  # path - a String of the filename path
  # position - Integer position of the offset in the diff
  # comments - list of `PullRequestReviewComment`s in this thread
  def initialize(pull: nil, pull_comparison:, path: nil, position: nil,
      line: nil, side: nil, start_diff_line: nil, end_diff_line: nil, comments: [], activerecord_pull_review_thread: nil)
    @pull = pull || pull_comparison.pull
    @pull_comparison = pull_comparison

    if path.nil? || path.is_a?(String)
      @path = path
    else
      raise TypeError, "expected path to be a String, but was #{path.class}"
    end

    if position.nil? || position.is_a?(Integer)
      @position = position
    else
      raise TypeError, "expected position to be a Integer, but was #{position.class}"
    end

    @line = line unless line.nil?
    @side = side unless side.nil?

    @start_diff_line = start_diff_line unless start_diff_line.nil?
    @end_diff_line = end_diff_line unless end_diff_line.nil?

    @comments = comments || []
    @comments.each { |c| c.thread = self }

    @activerecord_pull_review_thread = activerecord_pull_review_thread
  end

  attr_reader :pull, :pull_comparison, :path, :position, :subject_type
  attr_accessor :comments
  alias_method :pull_request, :pull

  def new_record?
    id.nil?
  end

  def id
    pull_request_review_thread_id
  end

  def pull_request_review_thread_id
    first_comment&.pull_request_review_thread&.id
  end

  def created_at
    first_comment.try(:created_at)
  end

  # See IssueTimeline
  def timeline_sort_by
    [created_at]
  end

  # Returns the number of unique authors in this thread.
  def author_count
    @author_count ||= begin
      authors = Set.new
      @comments.each do |c|
        authors << c.user
      end
      authors.size
    end
  end

  def old_style_review_thread?
    comments.first && comments.first.pull_request_review_id.nil?
  end

  # Create a new thread that clones the pull comparison, path, and position
  # of a pre-existing DeprecatedPullRequestReviewThread. Comments are empty so the thread
  # identifies itself as a new record and the `in_reply_to` form field is not sent.
  #
  # TODO This should not be needed when the inline_comment_form partial is cleaned up.
  def clone_without_comments
    self.class.new(
      pull_comparison: pull_comparison,
      path: path,
      position: position,
      line: line,
      side: side,
    )
  end

  def to_param
    id
  end

  def sort_key
    [path, position, id]
  end

  def reply_to_id
    first_comment&.id
  end

  def repository
    pull.repository
  end

  def legacy_thread?
    first_comment.legacy_comment?
  end

  def locked_for?(user)
    pull.locked_for?(user)
  end

  def visible_to?(viewer)
    comments.any? { |comment| comment.visible_to?(viewer) }
  end

  def comments_for(viewer)
    return @comments_for[viewer] if defined?(@comments_for)

    @comments_for = Hash.new do |hash, key|
      hash[key] = comments.select { |comment| comment.visible_to?(key) }
    end
    @comments_for[viewer]
  end

  def platform_type_name
    "PullRequestReviewThread"
  end

  def resolved?
    return @resolved if defined?(@resolved)
    @resolved = first_comment.pull_request_review_thread.resolver.present?
  end

  def resolved_by
    if resolved?
      first_comment.pull_request_review_thread.resolver
    end
  end

  def supports_multiple_threads_per_line?
    true
  end

  def ==(other)
    super || (other.instance_of?(self.class) && !id.nil? && id == other.id)
  end
  alias_method :eql?, :==

  def hash
    if id
      self.class.hash ^ id.hash
    else
      super
    end
  end

  # Public: The line number on which this thread is situated. blob position is 0 based offset, this
  # is 1 based offset, like normal file lines.
  def line
    return @line if defined?(@line)

    # Old comments don't have a blob position without extracting it via LegacyPositionData.
    # Ideally this property is populated by calling `async_position_data.then(&:blob_position)`
    # but that doesn't exist yet.
    return nil unless first_comment && blob_position
    @line = blob_position + 1
  end

  # Public: The GitHub::Diff::Line object that a multi-line comment starts on.
  #
  # Returns a GitHub::Diff::Line or nil if the comment failed to be positioned
  #         in the diff, or if the comment is not a multi-line comment.
  def start_diff_line
    return @start_diff_line if defined?(@start_diff_line)

    return nil unless first_comment && blob_position
    @start_diff_line = first_comment.async_start_line.sync
  end

  def start_line_type
    return nil unless start_diff_line
    case start_diff_line.type
    when :addition then "+"
    when :deletion then "-"
    else
      ""
    end
  end

  # Public: The GitHub::Diff::Line object that a multi-line comment ends on.
  #
  # Returns a GitHub::Diff::Line or nil if the comment failed to be positioned
  #         in the diff, or if the comment is not a multi-line comment.
  def end_diff_line
    return @end_diff_line if defined?(@end_diff_line)

    return nil unless first_comment && blob_position
    @end_diff_line = first_comment.async_end_line.sync
  end

  def end_line_type
    return nil unless end_diff_line
    case end_diff_line.type
    when :addition then "+"
    when :deletion then "-"
    else
      ""
    end
  end

  # Public: the side of the diff (removal or addition/context) on which the comment was left.
  def side
    return @side if defined?(@side)

    return nil unless first_comment && blob_position
    @side = left_blob ? :left : :right
  end

  memoize def activerecord_pull_request_review_thread
    @activerecord_pull_review_thread.presence || first_comment.pull_request_review_thread
  end

  # These seem like they belong on the thread itself rather than on each comment.
  delegate :live?, :outdated?, :pull_request_review, :pull_request_review_id,
    :diff_hunk_lines, :diff_entry, :current_diff_entry,
    :blob_position, :left_blob, :async_start_line,
    to: :first_comment

  delegate :on_file?,
    to: :activerecord_pull_request_review_thread

  protected def first_comment
    comments.first
  end
end
