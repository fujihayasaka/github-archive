# typed: true
# frozen_string_literal: true

module Organizations
  module Settings
    class RecommendedMemexProjectComponent < ApplicationComponent
      extend T::Sig

      include CachedOcticonHelper

      sig do
        params(
          # The MemexProject to which the MemexTemplate is linked
          memex_project: MemexProject,
          checked: T::Boolean,
          remaining_recommended_memex_projects_count: Integer,
        ).void
      end
      def initialize(
        memex_project:,
        checked:,
        remaining_recommended_memex_projects_count:
      )
        @memex_project = memex_project
        @checked = checked
        @remaining_recommended_memex_projects_count = remaining_recommended_memex_projects_count
      end

      def checked?
        @checked
      end

      private

      attr_reader :memex_project

      def input_attributes
        class_names(
          "checked" => checked?,
          "disabled" => @remaining_recommended_memex_projects_count < 1 && !checked?,
        )
      end
    end
  end
end
