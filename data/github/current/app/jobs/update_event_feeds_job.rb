# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: false
# frozen_string_literal: true

class UpdateEventFeedsJob < ApplicationJob
  extend Forwardable

  around_perform :use_mysql1_replica

  def_delegator :dogstats_tags, :all, :stats_tags

  set_max_redelivery_attempts 0
  queue_as :update_event_feeds

  before_perform prepend: true do
    event = arguments.first
    dogstats_tags.event = event
    Failbot.push(event_type: event.event_type)
  end

  # Updating event feeds should be exempt from the tenant context requirement.
  exempt_from_tenant_context_requirement

  def perform(event)
    if event.disabled?
      return GitHub.dogstats.increment("stratocaster_disabled", tags: stats_tags)
    end

    Stratocaster::Model.throttle do
      Stratocaster::Fanout.new(event: event, index: GitHub.stratocaster.index).perform
    end

    @success = true
  ensure
    dogstats_tags.success = !!@success
  end

  private

  def dogstats_tags
    @dogstats_tags ||= Stratocaster::DogstatsTags.new
  end
end
