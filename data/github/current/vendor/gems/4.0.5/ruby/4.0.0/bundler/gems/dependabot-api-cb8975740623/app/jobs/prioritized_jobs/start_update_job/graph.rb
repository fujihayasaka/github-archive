# frozen_string_literal: true

module PrioritizedJobs
  module StartUpdateJob
    class Graph < Default
      queue_as do
        :actions_dynamic_workflow_p4
      end
    end
  end
end
