# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class CheckAnnotationRange < Platform::Inputs::Base
      description "Information from a check run analysis to specific lines of code."

      argument :start_line, Int, "The starting line of the range.", required: true

      argument :start_column, Int, "The starting column of the range.", required: false

      argument :end_line, Int, "The ending line of the range.", required: true

      argument :end_column, Int, "The ending column of the range.", required: false

      argument :step_number, Int, "The step number of an annotation genereated by Actions", required: false, visibility: :internal
    end
  end
end
