# typed: true
# frozen_string_literal: true

class IntegrationTransfers::ShowView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :transfer
  delegate :integration, :requester, :target, to: :transfer

  def events
    return @events if defined?(@events)

    @events = []
    return @events unless integration.hook

    @events = integration.hook.events.map do |event|
      Hook::EventRegistry.for_event_type(event).display_name
    end.sort
  end
end
