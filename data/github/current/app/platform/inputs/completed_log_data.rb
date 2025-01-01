# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class CompletedLogData < Platform::Inputs::Base
      description "Information from a check step."
      visibility :internal

      argument :url, Scalars::URI, "The URL where this completed log can be found.", required: true
      argument :lines, Int, "The number of lines in the log.", required: true
    end
  end
end
