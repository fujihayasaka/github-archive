# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class CheckStepData < Platform::Inputs::Base
      description "Information from a check step."

      argument :name, String, "The name of the step.", required: false

      argument :number, Integer, "The index of the step.", required: false

      argument :completed_log, Inputs::CompletedLogData, "The completed log information", required: false

      argument :started_at, Scalars::DateTime, description: "Identifies the date and time when the check step was started.", required: false

      argument :completed_at, Scalars::DateTime, description: "Identifies the date and time when the check step was completed.", required: false

      argument :status, Enums::CheckStatusState, description: "The current status of the check step.", required: true

      argument :conclusion, Enums::CheckConclusionState, description: "The conclusion of the check step.", required: false

      argument :external_id, String, description: "A reference for the check step on the integrator's system.", required: false
    end
  end
end
