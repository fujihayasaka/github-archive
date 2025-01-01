# typed: true
# frozen_string_literal: true

module Actions
  module WorkflowRuns
    class CloneBannerComponent < ApplicationComponent

      def initialize(green_trees_enabled:, workflow_run:, current_repository:)
        # green_trees_enabled is the state of the actions_green_trees feature flag, remove once this ships
        @green_trees_enabled = green_trees_enabled
        @repository = current_repository
        @workflow_run = workflow_run
      end

      def render?
        @green_trees_enabled && (@workflow_run.is_clone? || @workflow_run.is_parent_of_clone?)
      end

      # if the workflow run is a clone, link out to the original workflow run
      def parent_run_url
        "#{@repository.permalink(include_host: true)}/actions/runs/#{@workflow_run.cloned_workflow_run_id}"
      end
    end
  end
end
