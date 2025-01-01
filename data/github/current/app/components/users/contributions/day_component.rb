# typed: true
# frozen_string_literal: true

module Users
  module Contributions
    class DayComponent < ApplicationComponent

      def initialize(level:, description: "", date: nil, as_table_cell: false, id: nil, **kwargs)
        @description = description
        @kwargs = kwargs
        @id = id

        @kwargs[:"data-date"] = date if date.present?
        @kwargs[:id] = id if id.present?

        if level.is_a?(Integer)
          @kwargs[:"data-level"] = level
        else
          # Make sure the contribution level exists in the enums
          @level = fetch_or_fallback(Platform::Enums::ContributionLevel.values.keys, level, "NONE")

          # Get the value 0-4
          @kwargs[:"data-level"] = T.must(Platform::Enums::ContributionLevel.values[@level]).value
        end

        @as_table_cell = as_table_cell
      end

      def descriptive_text
        content_tag(:span, @description, { class: "sr-only" })
      end

      def render_as_table_cell?
        @as_table_cell
      end
    end
  end
end
