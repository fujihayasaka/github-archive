# typed: true
# frozen_string_literal: true

module Reminders
  class RealTimeJob < ApplicationJob
    queue_as :reminders
    around_perform :set_readonly_db, :log_transaction_id
    before_enqueue :validate_arguments

    MAX_RETRY_ATTEMPTS = 5
    # Retry when expected records not found because replica may be behind
    retry_on ActiveRecord::RecordNotFound, wait: :polynomially_longer, attempts: MAX_RETRY_ATTEMPTS

    # These are OK to send to Failbot
    ALLOWED_KEYS = %w(
      ref
    )

    def perform(...)
      raise NotImplementedError
    end

    def queue_reminder_events(real_time_events)
      real_time_events.select(&:permitted?).uniq(&:dedup_key).each do |real_time_event|
        begin
          Hook::Event::ReminderEvent.queue(
            event_at:         event_at,
            actor:            real_time_event.actor,
            event_context:    real_time_event.context,
            event_type:       real_time_event.type,
            pull_request_ids: real_time_event.pull_request_ids,
            reminder:         real_time_event.reminder,
            repository_id:    real_time_event.repository_id,
          )
        rescue StandardError => e # rubocop:todo Lint/GenericRescue
          # Redact arguments that aren't known.
          # We can't send potentially private information here like repo names, etc.
          # As this could be anything, filter it heavily allowing only a subset of keys
          # to be sent to Failbot.

          # Report exception then continue processing other reminders
          failbot_args = sanitized_arguments(arguments.first)
          Failbot.report(e, failbot_args)

          # Allow errors to bubble up in test/dev
          raise e unless Rails.env.in?(%w(production staging))
        end
      end
    end

    def transaction_id
      params[:transaction_id] || "unknown"
    end

    def event_at
      params[:event_at] || Time.now
    end

    private

    def validate_arguments
      return if arguments.empty?
      return if arguments.size == 1 && arguments.first.is_a?(Hash)
      raise ArgumentError, "arguments passed to this job must be in a hash only"
    end

    def sanitized_arguments(args)
      return args if args.blank?

      args.each do |k, v|
        if v.is_a?(Hash)
          args[k] = sanitized_arguments(v)
          next
        end

        key = k.to_s
        next if key.end_with?("_id", "_at", "_on") # IDs and times are fine
        next if ALLOWED_KEYS.include?(key)
        args[k] = "[REDACTED]"
      end
    end

    def params
      arguments&.last || {}
    end

    def set_readonly_db
      ActiveRecord::Base.connected_to(role: :reading) do
        yield
      end
    end

    def log_transaction_id
      GitHub.logger.with_named_tags("gh.scheduled_reminders.transaction_id" => transaction_id) do
        yield
      end
    end
  end
end
