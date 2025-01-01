# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class WaitingOnResource < Platform::Inputs::Base
      description "Blocking resources"

      argument :check_run_id, ID, "Id of check run that is blocking.", required: false
      argument :check_suite_id, ID, "Id of check suite that is blocking.", required: false
      argument :identifier, String, "Identifier of the job that is blocking.", required: false
    end
  end
end
