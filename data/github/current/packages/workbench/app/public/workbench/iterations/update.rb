# typed: strict
# frozen_string_literal: true

module Workbench
  module Iterations
    class Update

      sig { params(workbench: Spark::Workbench, iteration: Spark::WorkbenchIteration, iteration_params: T::Hash[String, T.untyped]).returns(Spark::WorkbenchIteration) }
      def self.perform(workbench, iteration, iteration_params)
        # We'll set files in the events JSON column
        files = iteration_params.delete("files")
        Create.trim_prompt(iteration_params)

        if files
          iteration.events = {
            files: files,
          }
        end

        iteration.update(iteration_params)
        iteration
      end
    end
  end
end
