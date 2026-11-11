# typed: strict
# frozen_string_literal: true

module CopilotSessions
  module TaskApi
    # The valid fields allowable for sorting tasks via the CAPI "agents/tasks" endpoint.
    class SortField < T::Enum
      enums do
        LastUpdatedAt = new("last_updated_at")
        CreatedAt = new("created_at")
      end
    end
  end
end
