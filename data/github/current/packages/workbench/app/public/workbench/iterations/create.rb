# typed: strict
# frozen_string_literal: true

module Workbench
  module Iterations
    class Create

      sig { params(workbench: Spark::Workbench, iteration_params: T::Hash[String, T.untyped]).returns(Spark::WorkbenchIteration) }
      def self.perform(workbench, iteration_params)
        # We'll set files in the events JSON column
        files = iteration_params.delete("files")

        iteration = workbench.iterations.build(iteration_params)
        if !iteration_params.has_key?("parent_id")
          iteration.parent_id = workbench.current_iteration_id
        end

        if files
          iteration.events = {
            files: files,
          }
        end

        ApplicationRecord::Copilot.transaction do
          iteration.save
          workbench.update(current_iteration_id: iteration.id)
        end

        iteration
      end
    end
  end
end
