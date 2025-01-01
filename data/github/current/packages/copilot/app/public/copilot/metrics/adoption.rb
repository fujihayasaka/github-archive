# typed: strict
# frozen_string_literal: true

module Copilot
  module Metrics
    class Adoption
      include GitHub::Memoizer

      # We're using a rolling 28 day window for each period to determine activity. This means that if a seat has auth
      # or activity up to 28 days prior to a period, it will be considered authed or active for that period
      LOOKBACK_DAYS = 28
      OLDEST_ALLOWED_DAYS = 100
      MAX_WEEKS = 14
      CSV_HEADERS = %i[label startDate endDate total notOnboarded inactive active]

      TimePeriod = T.type_alias { { start: Date, end: Date, lookback_window: Date } }

      sig { returns(::Organization) }
      attr_reader :owner

      sig { params(owner: ::Organization).void }
      def initialize(owner:)
        @owner = owner
      end

      sig { returns(Copilot::Types::CurrentAdoptionMetricsPayload) }
      def current_payload
        unless owner.feature_enabled?(:copilot_metrics_access_page_updates) || owner.business&.feature_enabled?(:copilot_metrics_access_page_updates)
          return null_current_payload
        end

        seats = Copilot::Seat.for_owner(owner).pluck(:id)
        recent_authentications = Copilot::Authentication.for_organization(owner).where(authentication_at: LOOKBACK_DAYS.days.ago..).pluck(:copilot_seat_id)
        recent_activities = Copilot::Activity.for_organization(owner).where(activity_at: LOOKBACK_DAYS.days.ago..).pluck(:copilot_seat_id)

        {
          total: seats.count,
          active: recent_activities.count,
          inactive: (recent_authentications - recent_activities).count,
          dormant: (seats - recent_authentications).count,
        }
      end

      sig { returns(Copilot::Types::HistoricalAdoptionMetricsPayload) }
      def historical_payload
        {
          overallStartDate: trimmed_historical_data.first&.dig(:startDate) || Date.current,
          overallEndDate: trimmed_historical_data.last&.dig(:endDate) || Date.current,
          historicalAdoptionData: trimmed_historical_data,
        }
      end

      sig { returns(String) }
      def historical_csv
        CSV.generate do |csv|
          csv << CSV_HEADERS

          trimmed_historical_data.each do |row|
            csv_row = CSV_HEADERS.map { |header| row[header] }
            csv << csv_row
          end
        end
      end

      private

      sig { returns(Copilot::Types::CurrentAdoptionMetricsPayload) }
      def null_current_payload
        { total: 0, active: 0, inactive: 0, dormant: 0 }
      end

      sig { returns(T::Array[TimePeriod]) }
      memoize def time_periods
        latest_monday = T.cast(Date.current.beginning_of_week(:monday), Date)
        result = T.let([], T::Array[TimePeriod])
        MAX_WEEKS.times do |i|
          period_start = latest_monday - (i * 7).days
          period_end = T.cast([period_start + 6.days, Date.current].min, Date)
          lookback_window = period_start - LOOKBACK_DAYS.days

          next if Date.current - period_start > OLDEST_ALLOWED_DAYS.days # No weeks older than 100 days
          next if (period_end - period_start).to_i != 6 # Only full weeks

          result << { start: period_start, end: period_end, lookback_window: lookback_window }
        end

        result.reverse
      end

      sig { returns(Date) }
      memoize def earliest_start
        time_periods.map { |period| period[:start] }.min
      end

      sig { returns(Date) }
      memoize def latest_end
        time_periods.map { |period| period[:end] }.max
      end

      sig { returns(Date) }
      memoize def earliest_lookback
        time_periods.map { |period| period[:lookback_window] }.min
      end

      sig { returns(T::Array[Copilot::Types::HistoricalAdoptionMetricsBucket]) }
      memoize def trimmed_historical_data
        return [] unless historical_data.any?

        first_week_with_seats_index = historical_data.index { |bucket| bucket[:total] > 0 } || historical_data.size
        historical_data[first_week_with_seats_index..] || []
      end

      sig { returns(T::Array[Copilot::Types::HistoricalAdoptionMetricsBucket]) }
      memoize def historical_data
        # Pre-calculate which periods each seat has activity in
        activity_periods_by_seat = {}
        seat_activity_mapping.each do |seat_id, dates|
          activity_periods_by_seat[seat_id] = {}
          time_periods.each do |period|
            if dates.any? { |date| date >= period[:lookback_window] && date <= period[:end] }
              activity_periods_by_seat[seat_id][period[:start]] = true
            end
          end
        end

        # Pre-calculate which periods each seat has authentication in
        auth_periods_by_seat = {}
        auth_up_to_periods_by_seat = {}
        seat_auth_mapping.each do |seat_id, dates|
          auth_periods_by_seat[seat_id] = {}
          auth_up_to_periods_by_seat[seat_id] = {}

          time_periods.each do |period|
            # Auth in this period (including lookback)
            if dates.any? { |date| date >= period[:lookback_window] && date <= period[:end] }
              auth_periods_by_seat[seat_id][period[:start]] = true
            end

            # Auth up to this period
            if dates.any? { |date| date <= period[:end] }
              auth_up_to_periods_by_seat[seat_id][period[:start]] = true
            end
          end
        end

        time_periods.map do |period|
          seat_mapping_this_period = seat_period_mapping.select { |_, periods| periods[period[:start]] }
          seat_ids_this_period = seat_mapping_this_period.keys.to_set

          seats_with_activity = Set.new
          seats_with_auth_this_period = Set.new
          seats_with_auth_this_period_or_earlier = Set.new

          seat_ids_this_period.each do |seat_id|
            if activity_periods_by_seat.dig(seat_id, period[:start])
              seats_with_activity.add(seat_id)
            end

            if auth_periods_by_seat.dig(seat_id, period[:start])
              seats_with_auth_this_period.add(seat_id)
            end

            if auth_up_to_periods_by_seat.dig(seat_id, period[:start])
              seats_with_auth_this_period_or_earlier.add(seat_id)
            end
          end

          inactive_seats = seats_with_auth_this_period - seats_with_activity
          not_onboarded_seats = seat_ids_this_period - seats_with_auth_this_period_or_earlier

          {
            id: period[:start].to_s,
            label: "Week #{period[:start].cweek}",
            shortLabel: "W#{period[:start].cweek}",
            startDate: period[:start],
            endDate: period[:end],
            total: seat_ids_this_period.size,
            active: seats_with_activity.size,
            inactive: inactive_seats.size,
            notOnboarded: not_onboarded_seats.size
          }
        end
      end

      sig { returns(T::Hash[Integer, T::Hash[Date, T::Boolean]]) }
      memoize def seat_period_mapping
        seat_history_records = Copilot::SeatHistory
          .select(:seat_id, :seat_created_at, :seat_deleted_at)
          .where(owner_type: owner.type, owner_id: owner.id, seat_created_at: ..latest_end)
          .where("seat_deleted_at IS NULL OR seat_deleted_at > ?", earliest_start)

        result = {}
        seat_history_records.each do |history|
          result[history.seat_id] ||= {}

          # time_periods is sorted. Oldest first, newest last
          time_periods.each do |period|
            # A seat existed this period if it was created before the end of the period and not deleted before the
            # start of the period

            # If we've reached periods starting after this seat was deleted, we can break
            break if history.seat_deleted_at && period[:start] >= history.seat_deleted_at

            # Skip periods ending before this seat was created
            next if period[:end] < history.seat_created_at

            # If we get here, the seat existed in this period
            result[history.seat_id][period[:start]] = true
          end
        end

        result
      end

      sig { returns(T::Hash[Integer, T::Array[Date]]) }
      memoize def seat_activity_mapping
        result = {}

        activity_history = Copilot::ActivityHistory
          .select("copilot_activity_histories.copilot_seat_id, copilot_activity_histories.activity_date")
          .joins("INNER JOIN copilot_seat_histories ON copilot_activity_histories.copilot_seat_id = copilot_seat_histories.seat_id")
          .where("copilot_seat_histories.owner_type = ? AND copilot_seat_histories.owner_id = ?", owner.type, owner.id)
          .where("copilot_seat_histories.seat_created_at <= ?", latest_end)
          .where("copilot_seat_histories.seat_deleted_at IS NULL OR copilot_seat_histories.seat_deleted_at > ?", earliest_start)
          .where("copilot_activity_histories.activity_date BETWEEN ? AND ?", earliest_lookback, latest_end)
          .pluck(:copilot_seat_id, :activity_date)

        activity_history.each do |seat_id, date|
          result[seat_id] ||= []
          result[seat_id] << date
        end

        result
      end

      sig { returns(T::Hash[Integer, T::Array[Date]]) }
      memoize def seat_auth_mapping
        result = {}

        auth_history = Copilot::AuthenticationHistory
          .select("copilot_authentication_histories.copilot_seat_id, copilot_authentication_histories.authentication_date")
          .joins("INNER JOIN copilot_seat_histories ON copilot_authentication_histories.copilot_seat_id = copilot_seat_histories.seat_id")
          .where("copilot_seat_histories.owner_type = ? AND copilot_seat_histories.owner_id = ?", owner.type, owner.id)
          .where("copilot_seat_histories.seat_created_at <= ?", latest_end)
          .where("copilot_seat_histories.seat_deleted_at IS NULL OR copilot_seat_histories.seat_deleted_at > ?", earliest_start)
          .where("copilot_authentication_histories.authentication_date <= ?", latest_end)
          .pluck(:copilot_seat_id, :authentication_date)

        auth_history.each do |seat_id, date|
          result[seat_id] ||= []
          result[seat_id] << date
        end

        result
      end
    end
  end
end
