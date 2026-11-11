# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module DateSpanControllerHelper
    extend T::Helpers
    include GitHub::Memoizer

    abstract!

    requires_ancestor { ApplicationController }

    protected

    sig { overridable.returns(T.nilable(Date)) }
    def watermark_date
      nil
    end

    sig { returns(T.nilable(T.any({ period: String }, { from: String, to: String }))) }
    def initial_date_span
      if params.key?(:period)
        return if params.key?(:start_date) || params.key?(:end_date) # If both a period and daterange are provided, revert to default date span
        { period: sanitized_period } if sanitized_period
      elsif start_date && end_date
        { from: start_date&.strftime("%F"), to: end_date&.strftime("%F") }
      end
    end

    sig { returns(T.nilable(String)) }
    memoize def sanitized_period
      return unless params.key?(:period)
      %w[last14days last30days last90days].include?(params.fetch(:period)) ? params.fetch(:period) : nil
    end

    sig { returns(T.nilable(::Date)) }
    memoize def sanitized_start_date
      return unless params.key?(:start_date)
      Date.parse(params.fetch(:start_date))
    rescue # rubocop:disable Lint/RescueException
      nil
    end

    sig { returns(T.nilable(::Date)) }
    memoize def sanitized_end_date
      return unless params.key?(:end_date)
      Date.parse(params.fetch(:end_date))
    rescue # rubocop:disable Lint/RescueException
      nil
    end

    sig { returns(T.nilable(::Date)) }
    memoize def start_date
      start_date = sanitized_start_date
      return unless start_date

      tmp_end_date = sanitized_end_date
      return unless tmp_end_date

      # if the start_date happens after the end date, switch them
      start_date = tmp_end_date if start_date > tmp_end_date

      # if the start_date is further back than the max
      oldest_allowed_date = Time.current.utc.to_date - 2.years
      if watermark_date && T.must(watermark_date) > oldest_allowed_date
        oldest_allowed_date = watermark_date
      end
      start_date = oldest_allowed_date if start_date < oldest_allowed_date

      # if the start_date is equal to the end_date
      return if start_date == tmp_end_date

      start_date
    end

    sig { returns(T.nilable(::Date)) }
    memoize def end_date
      end_date = sanitized_end_date
      return unless end_date

      tmp_start_date = sanitized_start_date
      return unless tmp_start_date

      # if the end_date happens before the start_date, switch them
      end_date = tmp_start_date if end_date < tmp_start_date

      # if the end_date is in the future
      return if end_date > Time.current.utc.to_date

      # if the end_date is equal to the start_date
      return if tmp_start_date == end_date

      end_date
    end

    sig { returns(T::Boolean) }
    def valid_dates?
      return false if start_date.nil?
      return false if end_date.nil?
      return false if T.must(start_date) > T.must(end_date)
      true
    end

    sig { void }
    def ensure_dates
      render json: { error: "Must provide a valid start and end date" }, status: :bad_request unless valid_dates?
    end
  end
end
