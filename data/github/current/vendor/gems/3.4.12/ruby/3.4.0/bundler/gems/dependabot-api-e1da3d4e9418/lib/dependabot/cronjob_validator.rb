# frozen_string_literal: true

require "fugit"

module Dependabot
  module CronjobValidator
    def self.validate_cronjob_expression(cronjob_exp)
      result = Fugit.parse(cronjob_exp).class
      Dependabot::Logger.error("Invalid cronjob expression: #{cronjob_exp}") unless result == Fugit::Cron
      result
    end

    def self.next_run_elapsed_time(cronjob_exp)
      # calculate the next occurrence of cron job in hours, we raise validation error if
      # next job run is less than 24 hours later
      next_run_elapsed_time_hr = Fugit.parse(cronjob_exp).brute_frequency.delta_min / 3600
      Dependabot::Logger.info("Cron job next occurrence in #{next_run_elapsed_time_hr} hours for '#{cronjob_exp}'")

      next_run_elapsed_time_hr
    end

    def self.cronjob_match?(cronjob_exp, local_time) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      Rails.logger.info "Local time(original): #{local_time}. TimeZone: #{local_time.zone}"

      parsed_cronjob = Fugit.parse(cronjob_exp)
      if parsed_cronjob.nil?
        Rails.logger.error "Invalid cron expression"
        return false
      end
      if parsed_cronjob.hours.nil?
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
