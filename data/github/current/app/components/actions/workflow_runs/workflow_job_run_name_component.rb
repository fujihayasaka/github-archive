# typed: true
# frozen_string_literal: true

module Actions
  module WorkflowRuns
    class WorkflowJobRunNameComponent < ApplicationComponent
      attr_reader :split_display_name, :name, :can_split_name, :system_arguments

      def initialize(name:, can_split_name:, **system_arguments)
        @system_arguments = system_arguments
        @split_display_name = name&.split(" / ") || []
        @name = name
        @can_split_name = can_split_name
      end

      def short_first_path_name?
        split_display_name.first.length <= 3
      end

      def has_middle_paths?
        split_display_name.length > 2
      end
    end
  end
end
