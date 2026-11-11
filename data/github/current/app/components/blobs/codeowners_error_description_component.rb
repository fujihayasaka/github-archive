# typed: true
# frozen_string_literal: true

module Blobs
  class CodeownersErrorDescriptionComponent < ApplicationComponent
    attr_reader :error, :line_prefix, :line_error, :line_suffix,
      :error_offset, :end_offset

    MAX_ERROR_OFFSET = 30
    TRUNCATED_LINE_PREFIX = "…"

    def initialize(error)
      line = error.source.strip
      error_offset = error.column - 1
      end_offset = calculate_end_offset(error_offset, error.end_column, line)

      @error_offset = error_offset
      @end_offset = end_offset

      if error_offset > MAX_ERROR_OFFSET
        chars_to_trim = error_offset - MAX_ERROR_OFFSET
        line = TRUNCATED_LINE_PREFIX + line[chars_to_trim..-1]
        error_offset -= chars_to_trim - TRUNCATED_LINE_PREFIX.length
        end_offset -= chars_to_trim - TRUNCATED_LINE_PREFIX.length
      end

      @error = error

      @line_prefix = line[0...error_offset]
      @line_error = line[error_offset...end_offset]
      @line_suffix = line[end_offset..-1]
    end

    private

    def calculate_end_offset(error_offset, end_column, line)
      if end_column
        end_column
      elsif next_space_offset = line.index(" ", error_offset)
        next_space_offset
      else
        line.length
      end
    end
  end
end
