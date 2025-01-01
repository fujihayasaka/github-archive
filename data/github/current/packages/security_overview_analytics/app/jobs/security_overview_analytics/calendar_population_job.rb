# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  class CalendarPopulationJob < ApplicationJob
    extend T::Sig

    queue_as :security_overview_analytics_calendar_population
    locked_by timeout: 1.hour, key: DEFAULT_LOCK_PROC
    schedule interval: 1.day, scope: :global
    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    # The date from which we start populating the calendar
    # GHES was released in 2011, so we can safely assume that we don't need to go further back
    CALENDAR_START = T.let(::Date.new(2010, 1, 1), ::Date)

    BATCH_SIZE = 1000

    sig { params(start_date: T.nilable(::Date)).void }
    def perform(start_date = nil)
      GitHub.logger.info(
        "batch started",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "start_date": start_date,
      )

      if start_date.nil?
        db_max = SecurityOverviewAnalytics::Date.maximum(:date_value)

        GitHub.logger.info(
          "no start_date found in arguments, using last date in the database or starting from begnning of the calendar",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "db_max": db_max,
        )

        start_date =
          if db_max.nil?
            CALENDAR_START
          else
            # If we don't have a start date, we start from the last date in the database
            db_max + 1.day
          end
      end

      # Populating calendar 1 year into the future
      # Since this job is scheduled daily, this will keep growing
      end_date = Time.now.utc.to_date + 1.year
      date = start_date
      items_processed = 0
      items_created = 0

      with_write do
        while date <= end_date && items_processed < BATCH_SIZE
          SecurityOverviewAnalytics::Date
            .create_with(date_value: date)
            .find_or_create_by!(id: ::SecurityOverviewAnalytics::Date.id_from_date(date)) do
              # Callback block is called only when the record is created
              items_created += 1
            end

          date += 1.day
          items_processed += 1
        end
      end

      # If we have more dates left to process, we schedule another job to do it
      if date < end_date
        self.class.perform_later(date)
      end

      GitHub.logger.info(
        "calendar population batch completed",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.security_overview_analytics.dates_processed": items_processed,
        "gh.security_overview_analytics.dates_created": items_created,
        "gh.security_overview_analytics.started_at_date": start_date,
        "gh.security_overview_analytics.ended_at_date": end_date,
        "gh.security_overview_analytics.more_dates_to_process": date < end_date,
      )
    end
  end
end
