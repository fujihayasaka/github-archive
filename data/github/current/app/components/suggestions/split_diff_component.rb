# typed: strict
# frozen_string_literal: true

class Suggestions::SplitDiffComponent < ApplicationComponent
  sig { returns(GitHub::Diff::Entry) }
  attr_reader :diff_entry

  sig { returns(Repository) }
  attr_reader :repository

  sig { returns(String) }
  attr_reader :alert_commit_oid

  sig { returns(T.nilable(T::Array[String])) }
  attr_reader :file_highlighting

  sig { returns(T.untyped) }
  attr_reader :alert_location

  renders_one :annotation_on_alert_location

  sig do
    params(
      diff_entry: GitHub::Diff::Entry,
      repository: Repository,
      alert_commit_oid: String,
      file_highlighting: T.nilable(T::Array[String]),
      alert_location: T.untyped,
    ).void
  end
  def initialize(diff_entry:, repository:, alert_commit_oid:, file_highlighting: nil, alert_location: nil)
    @diff_entry = diff_entry
    @repository = repository
    @alert_commit_oid = alert_commit_oid
    @file_highlighting = file_highlighting
    @alert_location = alert_location
  end

  sig { returns(String) }
  def line_range_suffix
    if start_line.present?
      ":#{start_line}"
    else
      ""
    end
  end

  sig { returns(String) }
  def path_link
    anchor = if start_line.present?
      "L#{start_line}"
    end

    blob_path(diff_entry.path, alert_commit_oid, repository, anchor:)
  end

  sig { returns(String) }
  def copy_path
    diff_entry.a_path + line_range_suffix
  end

  sig { returns(String) }
  def truncated_file_path
    helpers.reverse_truncate(diff_entry.path, length: DiffHelper::DIFF_FILE_LABEL_TRUNCATION_LENGTH)
  end

  sig { returns(String) }
  def file_path
    file_components[0]
  end

  sig { returns(String) }
  def file_name
    file_components[1]
  end

  sig { returns(T.nilable(Integer)) }
  memoize def start_line
    start_line = T.let(nil, T.nilable(Integer))

    diff_entry.split_lines.each do |left, _right|
      if left.type != :addition && left.type != :deletion
        next
      end

      start_line = T.let(left.left, Integer)
      break
    end

    if start_line.nil?
      # If no start line was found, use the first line of the right entry
      diff_entry.split_lines.each do |_left, right|
        if right.type != :addition && right.type != :deletion
          next
        end

        start_line = T.let(right.right, Integer)
        break
      end
    end

    start_line
  end

  sig { params(left_line: GitHub::Diff::Line).returns(T::Boolean) }
  def alert_ends_on_line?(left_line)
    alert_location&.file_path == diff_entry.path && alert_location&.end_line == left_line.left
  end

  sig { returns(T::Boolean) }
  def should_display_fallback_annotation?
    alert_location&.file_path == diff_entry.path &&
      !diff_entry.split_lines.any? { |lines| alert_ends_on_line?(lines[0]) }
  end

  private

  # returns a [file_path, file_name] pair
  sig { returns([String, String]) }
  def file_components
    helpers.split_file_path_and_name(truncated_file_path)
  end
end
