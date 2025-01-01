# typed: strict
# frozen_string_literal: true

module Workbench
  module Iterations
    class Delete
      sig { params(workbench: Spark::Workbench, iteration: Spark::WorkbenchIteration).returns(Spark::WorkbenchIteration) }
      def self.perform(workbench, iteration)
        ApplicationRecord::Copilot.transaction do
          workbench.update(current_iteration_id: iteration.parent_id)
          iteration.destroy
        end

        iteration
      end
    end
  end
end
