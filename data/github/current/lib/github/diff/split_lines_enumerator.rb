# typed: false
# frozen_string_literal: true

class GitHub::Diff::SplitLinesEnumerator
  include Enumerable

  # Public: Create a new split diff lines Enumerator.
  #
  # lines - Enumerable of String lines
  #
  # Returns an Enumerator that yields pairs of GitHub::Diff::Line objects: one
  # for the left side of the diff and one for the right side.
  def initialize(lines)
    @lines = lines
  end

  def each(&block)
    return enum_for(:each) unless block

    @additions, @deletions = [], []

    last_line = GitHub::Diff::Line::EMPTY
    GitHub::Diff::Enumerator.new(@lines).each do |line|
      case line.type
      when :hunk, :context, :injected_context
        flush(&block)
        block.call([line, line])
      when :addition
        @additions << line
      when :deletion
        @deletions << line
      else
        raise TypeError, "unknown diff type: #{type.inspect}"
      end
      last_line = line
    end

    flush(&block)
  end

  private

  # Flush out accumulated additions and deletions
  def flush
    related = @additions.length == @deletions.length
    while @additions.any? || @deletions.any?
      left = @deletions.shift || GitHub::Diff::Line::EMPTY
      right = @additions.shift || GitHub::Diff::Line::EMPTY
      if related
        left.related_line = right
        right.related_line = left
      end
      yield [left, right]
    end
  end
end
