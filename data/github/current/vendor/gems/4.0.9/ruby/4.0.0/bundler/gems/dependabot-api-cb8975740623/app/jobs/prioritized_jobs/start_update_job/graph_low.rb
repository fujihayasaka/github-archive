# frozen_string_literal: true

module PrioritizedJobs
  module StartUpdateJob
    class GraphLow < Default
      queue_as do
        :actions_dynamic_workflow_p5
      end
    end
  end
end
