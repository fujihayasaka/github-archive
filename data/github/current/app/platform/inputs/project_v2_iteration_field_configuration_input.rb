# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class ProjectV2IterationFieldConfigurationInput < Platform::Inputs::Base
      description "Represents an iteration field configuration."

      argument :start_date, Scalars::Date, "The start date for the first iteration.", required: true
      argument :duration, Integer, "The duration of each iteration, in days.", required: true
      argument :iterations, [Inputs::ProjectV2Iteration], "Zero or more iterations for the field.", required: true
    end
  end
end
