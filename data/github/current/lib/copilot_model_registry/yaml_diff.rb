# typed: strict
# frozen_string_literal: true

require "diff/lcs"

module CopilotModelRegistry
  # Computes line-by-line diffs between YAML strings for the review UI.
  module YamlDiff
    # A single line in a diff result.
    # type: :unchanged, :added, :removed, :changed
    # old_line_num / new_line_num: 1-based line numbers (nil when not applicable)
    DiffLine = T.type_alias do
      {
        type: Symbol,
        old_line_num: T.nilable(Integer),
        new_line_num: T.nilable(Integer),
        old_text: T.nilable(String),
        new_text: T.nilable(String),
      }
    end

    # Computes a structured diff between two YAML strings.
    # Returns an array of DiffLine hashes suitable for rendering in the review UI.
    #
    # For new models (before_yaml is empty/nil), all lines are marked as :added.
    # For unchanged content, all lines are marked as :unchanged.
    sig { params(before_yaml: T.nilable(String), after_yaml: String).returns(T::Array[DiffLine]) }
    def self.compute(before_yaml, after_yaml)
      before_lines = (before_yaml || "").lines.map(&:chomp)
      after_lines = after_yaml.lines.map(&:chomp)

      diffs = Diff::LCS.sdiff(before_lines, after_lines)
      result = T.let([], T::Array[DiffLine])

      diffs.each do |change|
        case change.action
        when "="
          result << {
            type: :unchanged,
            old_line_num: change.old_position + 1,
            new_line_num: change.new_position + 1,
            old_text: change.old_element,
            new_text: change.new_element,
          }
        when "!"
          result << {
            type: :changed,
            old_line_num: change.old_position + 1,
            new_line_num: change.new_position + 1,
            old_text: change.old_element,
            new_text: change.new_element,
          }
        when "-"
          result << {
            type: :removed,
            old_line_num: change.old_position + 1,
            new_line_num: nil,
            old_text: change.old_element,
            new_text: nil,
          }
        when "+"
          result << {
            type: :added,
            old_line_num: nil,
            new_line_num: change.new_position + 1,
            old_text: nil,
            new_text: change.new_element,
          }
        end
      end

      result
    end

    # Returns a unified diff string (like git diff) for the diff-only view.
    sig { params(before_yaml: T.nilable(String), after_yaml: String).returns(String) }
    def self.unified_diff(before_yaml, after_yaml)
      before_lines = (before_yaml || "").lines.map(&:chomp)
      after_lines = after_yaml.lines.map(&:chomp)

      hunks = Diff::LCS.diff(before_lines, after_lines)
      return "" if hunks.empty?

      output = T.let([], T::Array[String])
      output << "--- current"
      output << "+++ proposed"

      hunks.each do |hunk|
        first_change = hunk.first
        last_change = hunk.last

        old_start = [first_change.position + 1, 1].max
        old_count = hunk.count { |c| c.action == "-" }
        new_start = [first_change.position + 1, 1].max
        new_count = hunk.count { |c| c.action == "+" }

        output << "@@ -#{old_start},#{old_count} +#{new_start},#{new_count} @@"

        hunk.each do |change|
          case change.action
          when "-"
            output << "-#{change.element}"
          when "+"
            output << "+#{change.element}"
          end
        end
      end

      output.join("\n")
    end

    # Returns summary stats for the diff.
    sig { params(diff_lines: T::Array[DiffLine]).returns({ additions: Integer, deletions: Integer, changes: Integer }) }
    def self.stats(diff_lines)
      additions = diff_lines.count { |l| l[:type] == :added }
      deletions = diff_lines.count { |l| l[:type] == :removed }
      changes = diff_lines.count { |l| l[:type] == :changed }
      { additions: additions, deletions: deletions, changes: changes }
    end

    # Returns true if this is a new model (no existing content).
    sig { params(before_yaml: T.nilable(String)).returns(T::Boolean) }
    def self.new_model?(before_yaml)
      before_yaml.nil? || before_yaml.strip.empty?
    end
  end
end
