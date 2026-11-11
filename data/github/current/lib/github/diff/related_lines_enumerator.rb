# typed: true
# frozen_string_literal: true

class GitHub::Diff::RelatedLinesEnumerator
  include Enumerable

  # Public: Create a new related diff lines Enumerator.
  #
  # lines - Enumerable of String lines
  #
  # Returns an Enumerator that yields GitHub::Diff::Line objects, possibly with
  # their #related_line attributes set.
  def initialize(lines, position_offset = 0)
    @lines = lines
    @position_offset = position_offset
  end

  def each(&block)
    return enum_for(:each) unless block
    @buffer = []

    GitHub::Diff::Enumerator.new(@lines, @position_offset).each do |line|
      case line.type
      when :hunk, :context, :injected_context
        flush(&block)
        block.call(line)
      when :addition, :deletion
        @buffer << line
      else
        raise TypeError, "unknown diff type: #{line.type.inspect}"
      end
    end

    flush(&block)
  end

  private

  # Flush out accumulated additions and deletions
  def flush
    additions = @buffer.select { |line| line.type == :addition }
    deletions = @buffer.select { |line| line.type == :deletion }
    related   = additions.length == deletions.length

    while line = @buffer.shift
      related_line = if related
        case line.type
        when :addition
          deletions.shift
        when :deletion
          additions.shift
        end
      else
        nil
      end

      line.related_line = related_line
      yield line
    end
  end
end
