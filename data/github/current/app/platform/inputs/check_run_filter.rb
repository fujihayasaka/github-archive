# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class CheckRunFilter < Platform::Inputs::Base
      description "The filters that are available when fetching check runs."

      argument :check_type, Enums::CheckRunType, "Filters the check runs by this type.", required: false

      argument :app_id, Int, "Filters the check runs created by this application ID.", required: false

      argument :check_name, String, "Filters the check runs by this name.", required: false

      argument :status, Enums::CheckStatusState, "Filters the check runs by this status. Superceded by statuses.", required: false

      argument :statuses, [Enums::CheckStatusState], "Filters the check runs by this status. Overrides status.", required: false

      argument :conclusions, [Enums::CheckConclusionState], "Filters the check runs by these conclusions.", required: false
    end
  end
end
