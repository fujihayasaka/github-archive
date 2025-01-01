# typed: true
# frozen_string_literal: true

class ReviewThreadCreator
  def initialize(
    author:,
    pull: nil,
    review:,
    diff_range: {},
    path:,
    body:,
    line: nil,
    side: :right,
    start_line: nil,
    start_side: :right,
    subject_type: :line,
    submit_review: false
  )

    @author = author
    @pull = pull
    @review = review
    @diff_range = diff_range
    @path = path
    @body = body
    @line = line
    @side = side
    @start_line = start_line
    @start_side = start_side
    @subject_type = subject_type
    @submit_review = submit_review
  end

  def create_thread
    async_create_thread.sync
  end

  def async_create_thread
    async_pull = if pull
      Promise.resolve(pull)
    else
      review.async_pull_request
    end

    async_pull.then do |pull|
      context_lines = compute_context_lines(
        end_line: line,
        path: path,
        repository: pull.head_repository,
        start_line: start_line,
        subject_type: subject_type,
      )
      async_diff(pull: pull, diff_range: diff_range, context_lines: context_lines).then do |diff|
        thread = review.build_thread(subject_type: subject_type)
        thread.creation_diff = diff if pull.repository&.feature_enabled?(:comment_outside_the_diff)

        comment = thread.build_first_comment(
          user: author,
          diff: diff,
          body: body,
          path: path,
          line: line,
          side: side,
          start_line: start_line,
          start_side: start_side
        )

        if thread.save
          review.comment! if submit_review
        end

        [thread, comment]
      end
    end
  end

  private

  attr_reader :author, :pull, :review, :diff_range, :path, :body,
    :line, :side, :start_line, :start_side, :subject_type, :submit_review

  def async_diff(pull:, diff_range:, context_lines:)
    start_commit_oid = diff_range[:start_commit_oid] || merge_base(pull)
    end_commit_oid ||= diff_range[:end_commit_oid] || pull.head_sha
    base_commit_oid ||= diff_range[:base_commit_oid] || merge_base(pull)
    pull.async_compare_repository.then do |repo|
      GitHub::Diff.new(
        repo, start_commit_oid, end_commit_oid,
        base_sha: base_commit_oid,
        context_lines: context_lines
      )
    end
  end

  # avoid redundant load (not memozied on model)
  def merge_base(pull)
    @merge_base ||= pull.merge_base
  end

  def compute_context_lines(repository:, path:, start_line:, end_line:, subject_type:)
    return unless repository&.feature_enabled?(:comment_outside_the_diff)
    # do not compute additional context lines if we are not creating a line-level thread
    return unless subject_type&.to_sym == :line
    start_line ||= end_line
    range = Range.new(start_line - 4, end_line + 6)
    {
      path => [range]
    }
  end
end
