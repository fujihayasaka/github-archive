# typed: strict
# frozen_string_literal: true

module CopilotSessions
  # The valid fields allowable for sorting tasks via the CAPI "agents/sessions/resources" endpoint.
  # Currently this only has one value but we anticipate more fields being added in the future (such as
  # created_at).
  # rubocop:disable Sorbet/MultipleTEnumValues
  class TaskSortField < T::Enum
    enums do
      LastUpdatedAt = new("last_updated_at")
    end
  end
  # rubocop:enable Sorbet/MultipleTEnumValues
end
