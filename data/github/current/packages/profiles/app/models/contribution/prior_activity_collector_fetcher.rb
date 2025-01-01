# typed: false
# frozen_string_literal: true

# Public: Used to determine the most recent Contribution::Collector that contains user
# contributions, prior to the time span of a given Contribution::Collector.
class Contribution::PriorActivityCollectorFetcher
  attr_reader :collector

  # collector - Contribution::Collector instance to use as a starting point
  def initialize(collector:)
    @collector = collector
  end

  delegate :organization_id, :user, :contribution_classes, :viewer,
    :excluded_organization_ids, to: :collector

  # Public: Get a collector for a time span where the user had contributions. Will occur before the
  # time span of the given collector.
  #
  # Returns a Contribution::Collector or nil.
  def collector_with_activity
    return @collector_with_activity if defined?(@collector_with_activity)
    fetch
    @collector_with_activity
  end

  # Public: Get a collector for a time span where the user had no contributions. Will occur on
  # or before the time span of the given collector.
  #
  # Returns a Contribution::Collector or nil.
  def collector_without_activity
    return @collector_without_activity if defined?(@collector_without_activity)
    fetch
    @collector_without_activity
  end

  # Public: Get the time span during which the user made no contributions. Will go from the month
  # after the month containing the user's latest contribution that was made prior to the given
  # collector, up to the end of the time span of the given collector.
  #
  # Example: User has contribution in May. Given collector is August. The time range returned will
  # be for the start of June through the end of August.
  #
  # Returns a Range of Times or nil.
  def time_range_without_activity
    return @time_range_without_activity if defined?(@time_range_without_activity)
    fetch
    @time_range_without_activity
  end

  # Public: Get a date range for either the month with contributions prior to the given collector,
  # or for the earliest month that the user had no contributions. Will only go back as far as
  # January of the year of the given collector.
  #
  # Returns a Range of Dates or nil.
  def date_range
    prior_month_collector = collector_with_activity || collector_without_activity
    prior_month_collector.try(:date_range)
  end

  private

  def fetch
    return if @collector.any_contribution?

    time_range = collector.time_range
    latest_time = time_range.end
    prior_month = time_range.begin - 1.month
    @collector_without_activity = @collector
    previous_month_collector = nil

    while !@collector_without_activity.any_contribution?
      break if prior_month.month != latest_time.month

      from = prior_month.beginning_of_month
      previous_month_collector = Contribution::Collector.new(
        organization_id: organization_id,
        user: user,
        viewer: viewer,
        contribution_classes: contribution_classes,
        time_range: from..from.end_of_month,
        excluded_organization_ids: excluded_organization_ids,
        lightweight: @collector.lightweight?
      )

      break if previous_month_collector.any_contribution?

      prior_month = previous_month_collector.time_range.begin - 1.month
      @collector_without_activity = previous_month_collector
    end

    earliest_date = @collector_without_activity.time_range.begin
    @time_range_without_activity = earliest_date..latest_time

    @collector_with_activity = if previous_month_collector&.any_contribution?
      previous_month_collector
    end
  end
end
