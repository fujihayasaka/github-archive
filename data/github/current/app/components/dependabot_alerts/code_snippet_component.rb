# typed: true
# frozen_string_literal: true

module DependabotAlerts
  class CodeSnippetComponent < ApplicationComponent
    include UrlHelper
    include EditorConfigHelper

    delegate :current_repository, to: :helpers

    attr_reader :blob, :commit, :location, :message_link, :message_text, :context_line_count, :highlight_location_lines

    def initialize(
      blob,
      location,
      commit: nil,
      message_link: nil,
      message_text: nil,
      context_line_count: 3,
      highlight_location_lines: true
    )
      @blob = blob
      @commit = commit
      # Ensures start column is always 1-based if end column is present
      normalized_start_column = location[:start_column]
      if normalized_start_column.zero? && location[:end_column].nonzero?
        normalized_start_column = 1
      end
      @location = Location.new(
        location[:start_line],
        location[:end_line],
        normalized_start_column,
        location[:end_column],
      )
      @message_text = message_text
      @message_link = message_link
      @context_line_count = context_line_count
      @highlight_location_lines = highlight_location_lines
    end

    def lines
      blob.colorized_lines
    end

    def lines_to_include
      (location.start_line - context_line_count..location.end_line + context_line_count).to_a
    end

    def lines_to_highlight
      if highlight_location_lines
        (location.start_line..location.end_line).to_a
      else
        []
      end
    end

    def highlight?(line_number)
      lines_to_highlight.include?(line_number)
    end

    def last_line_to_highlight?(line_number)
      line_number == lines_to_highlight.last
    end

    # Returns an HTML class string to set appropriate highlighting for a line
    def line_highlight_classes(line_number)
      highlight?(line_number) ? "color-bg-attention" : ""
    end

  end
end
