# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class ProjectV2Iteration < Platform::Inputs::Base
      description "Represents an iteration"

      argument :start_date, Scalars::Date, "The start date for the iteration.", required: true
      argument :duration, Integer, "The duration of the iteration, in days.", required: true
      argument :title, String, "The title for the iteration.", required: true
    end
  end
end
