# typed: strict
# frozen_string_literal: true

require "fugit"

module Dependabot
  module CronjobValidator
    extend T::Sig

    MIN_INTERVAL_BETWEEN_RUNS = T.let(24.hours, ActiveSupport::Duration)
    MAX_INTERVAL_BETWEEN_RUNS = T.let(1.year, ActiveSupport::Duration)

    class InvalidCronjobExpressionError < ArgumentError; end

    sig { params(cronjob_exp: String).void }
    def self.validate_cronjob_expression(cronjob_exp)
      parsed = Fugit.parse(cronjob_exp)

      unless parsed.is_a?(Fugit::Cron)
        raise InvalidCronjobExpressionError, "Invalid cronjob expression: '#{cronjob_exp}'."
      end

      if parsed.timezone
        raise InvalidCronjobExpressionError,
              "Cronjob expression must not include a timezone: '#{cronjob_exp}'; use the 'timezone' property instead."
      end

      # Cron intervals can vary... eg, the first of every month can result in intervals of 28, 30, or 31 days
      min_interval = parsed.brute_frequency.delta_min.seconds
      max_interval = parsed.brute_frequency.delta_max.seconds
      if min_interval < MIN_INTERVAL_BETWEEN_RUNS
        raise InvalidCronjobExpressionError,
              "Cronjob expression '#{cronjob_exp}' has a minimum interval of #{min_interval.in_hours.to_i} hours " \
              "which is less than the minimum allowed interval of #{MIN_INTERVAL_BETWEEN_RUNS.in_hours.to_i} hours."
      elsif max_interval > MAX_INTERVAL_BETWEEN_RUNS
        raise InvalidCronjobExpressionError,
              "Cronjob expression '#{cronjob_exp}' has a maximum interval of #{max_interval.in_hours.to_i} hours " \
              "which is greater than the maximum allowed interval of " \
              "#{MAX_INTERVAL_BETWEEN_RUNS.in_hours.to_i} hours (1 year)."
      end
    end

    sig { params(cronjob_exp: String, local_time: Time).returns(T::Boolean) }
    def self.cronjob_match?(cronjob_exp, local_time) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      Rails.logger.info "Local time(original): #{local_time}. TimeZone: #{local_time.zone}"

      parsed_cronjob = Fugit.parse(cronjob_exp)
      unless parsed_cronjob.is_a?(Fugit::Cron)
        Rails.logger.error "Invalid cron expression"
        return false
      end
      if !parsed_cronjob.respond_to?(:hours) || parsed_cronjob.hours.nil?
        Rails.logger.error "Cron expression does not have hour section, would run more than once a day"
        return false
      end

      # removes minute component from local time for comparision
      time_to_compare = Time.utc(local_time.year, local_time.month, local_time.day, local_time.hour, 0)
      minutes_section = parsed_cronjob.original[/\d+/]

      cronjob_modified = if minutes_section.to_i.positive?
                           # if we find minutes in cron expression, we remove it as we only
                           # require hour section for comparison
                           Rails.logger.info "Cron expression-minutes: #{minutes_section}"
                           Fugit.parse(parsed_cronjob.original.sub(/\d+/, "0"))
                         else
                           parsed_cronjob
                         end

      Rails.logger.info "Cron expression-original: #{cronjob_exp}. Cron expression-modified: " \
                        "#{cronjob_modified.original}. Cron derived time, hour: #{cronjob_modified.hours[0]}" \
                        ". minutes: #{cronjob_modified.minutes[0]}. Local time(compare): #{time_to_compare}. " \
                        "match outcome: #{cronjob_modified.match?(time_to_compare.to_s.sub(' UTC', ''))}"
      cronjob_modified.match?(time_to_compare.to_s.sub(" UTC", ""))
    end
  end
end
