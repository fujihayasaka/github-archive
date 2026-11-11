# typed: true
# frozen_string_literal: true

class Stafftools::VssSubscriptionEvents::EventComponent < ApplicationComponent
  attr_reader :event

  delegate :id, :created_at, :investigation_notes, to: :event
  delegate :subscription_id, :operation, :email, to: :parsed_event

  def initialize(event:)
    @event = event
  end

  def status
    event.status.humanize.titleize
  end

  private

  memoize def parsed_event
    ::Licensing::Vss::ParsedSubscriptionEvent.new(event.payload)
  end
end
