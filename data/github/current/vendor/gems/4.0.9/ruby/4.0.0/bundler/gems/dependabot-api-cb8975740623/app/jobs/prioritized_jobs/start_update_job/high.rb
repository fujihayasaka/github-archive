# frozen_string_literal: true

module PrioritizedJobs
  module StartUpdateJob
    class High < Default
      queue_as do
        :actions_dynamic_workflow_p1
      end
    end
  end
end
