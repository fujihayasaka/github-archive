# typed: false
# frozen_string_literal: true

# Enumerate lines from raw diff text with diff position, line type, and line
# number tracking. This is useful for rendering table-style diff interfaces.
#
# Note that this code has been optimized to reduce object allocations,
# because that has been measured to improve the performance
# significantly. Thus, for example, `line_type` uses `start_with?`
# rather than the more natural approach of examining `line[0]`,
# because the latter would require an extra String object to be
# allocated.
class GitHub::Diff::Enumerator
  include Enumerable

  def self.line_type(line)
    return unless line
    case
    when line.start_with?("@"); :hunk
    when line.start_with?("+"); :addition
    when line.start_with?("-"); :deletion
    when line.start_with?(" "); :context
    when line.start_with?("~"); :injected_context
    when line.start_with?("\\"); :nonewline
    end
  end

  # Public: Create a new diff lines Enumerator.
  #
  # lines - Enumerable of String lines
  #
  # Returns an Enumerator that yields GitHub::Diff::Line objects.
  def initialize(lines, position_offset = 0)
    @lines = lines
    @position_offset = position_offset
  end

  # These lines show the before/after filenames.
  FILE_A_PATTERN = /\A\-\-\- \w\/./
  FILE_B_PATTERN = /\A\+\+\+ \w\/./

  HUNK_HEADER_PATTERN = /\A@@ \-(?<left>\d+)(?:,\d+)? \+(?<right>\d+)/

  def each(&block)
    return enum_for(:each) unless block_given?

    # Skip over the file header:
    start = 0
    start += 1 if (next_line = @lines[start]) && next_line =~ FILE_A_PATTERN
    start += 1 if (next_line = @lines[start]) && next_line =~ FILE_B_PATTERN

    current = left = right = nil
    next_type = self.class.line_type(@lines[start])
    start.upto(@lines.size - 1).each do |index|
      line = @lines[index]
      type = next_type
      next_type = self.class.line_type(@lines[index + 1])

      case type
      when :addition
        current = (right += 1) unless right.nil?
      when :deletion
        current = (left += 1)
      when :context, :injected_context
        left  += 1 unless left.nil?
        right += 1 unless right.nil?
        current = right unless right.nil?
      when :hunk
        if match = line.match(HUNK_HEADER_PATTERN)
          left = match[:left].to_i - 1
          right = match[:right].to_i - 1
          current = right
        else
          fail "Invalid hunk marker: #{line.inspect}"
        end
      when :nonewline
        next
      else
        fail "Unexpected diff text: #{line.inspect}"
      end

      yield GitHub::Diff::Line.new(
              type: type, text: line, position: index + @position_offset,
              left: left, right: right, current: current,
              nonewline: next_type == :nonewline)
    end
  end
end
