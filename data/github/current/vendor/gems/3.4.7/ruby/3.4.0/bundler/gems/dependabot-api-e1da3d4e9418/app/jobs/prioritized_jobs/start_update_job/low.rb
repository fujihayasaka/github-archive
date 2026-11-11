# frozen_string_literal: true

module PrioritizedJobs
  module StartUpdateJob
    class Low < Default
      queue_as do
        :actions_dynamic_workflow_p3
      end
    end
  end
end
