# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class CheckRunAction < Platform::Inputs::Base
      description "Possible further actions the integrator can perform."

      argument :label, String, "The text to be displayed on a button in the web UI.", required: true
      argument :description, String, "A short explanation of what this action would do.", required: true
      argument :identifier, String, "A reference for the action on the integrator's system. ", required: true
    end
  end
end
