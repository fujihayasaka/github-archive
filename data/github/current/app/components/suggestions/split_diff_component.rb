# typed: strict
# frozen_string_literal: true

class Suggestions::SplitDiffComponent < ApplicationComponent
  extend T::Sig

  sig { returns(GitHub::Diff::Entry) }
  attr_reader :diff_entry

  sig { returns(T.nilable(T::Array[String])) }
  attr_reader :file_highlighting

  sig { returns(T.untyped) }
  attr_reader :alert_location

  sig { returns(T.nilable(String)) }
  attr_reader :path_link

  renders_one :annotation_on_alert_location

  sig do
    params(
      diff_entry: GitHub::Diff::Entry,
      file_highlighting: T.nilable(T::Array[String]),
      alert_location: T.untyped,
      path_link: T.nilable(String),
    ).void
  end
  def initialize(diff_entry:, file_highlighting: nil, alert_location: nil, path_link: nil)
    @diff_entry = diff_entry
    @file_highlighting = file_highlighting
    @alert_location = alert_location
    @path_link = path_link
  end

  sig { returns(String) }
  def line_range_suffix
    suffix = alert_location&.start_line.present? ? ":#{alert_location.start_line}" : ""
    # Show the end line if it differs from the start line
    if !suffix.empty? && alert_location&.end_line.present? && alert_location.start_line != alert_location.end_line
      suffix += "-#{alert_location.end_line}"
    end
    suffix
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
