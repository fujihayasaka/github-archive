# typed: strict
# frozen_string_literal: true

module CopilotSessions
  # The valid directions allowable for sorting via the CAPI endpoints.
  class SortDirection < T::Enum
    enums do
      Asc = new
      Desc = new
    end
  end
end
