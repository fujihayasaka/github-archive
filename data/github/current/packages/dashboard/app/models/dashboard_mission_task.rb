# typed: true
# frozen_string_literal: true

class DashboardMissionTask
  attr_reader :label, :completion_link_path, :completion_link_method, :hydro_event_target

  def initialize(
    label:,
    complete:,
    completion_link_path:,
    completion_link_method: :get,
    hydro_event_target:
  )
    @label = label
    @complete = complete
    @completion_link_path = completion_link_path
    @completion_link_method = completion_link_method
    @hydro_event_target = hydro_event_target
  end

  def complete?
    @complete
  end
end
