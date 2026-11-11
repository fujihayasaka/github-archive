# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class HookDeliveryRaceConditionCheckJob < ApplicationJob
  default_to_write_connection! # rubocop:todo GitHub/JobsDoNotDefaultToWriteConnection

  queue_as :hook_delivery_race_condition_check

  retry_on StandardError, wait: :polynomially_longer

  retry_on_dirty_exit

  def self.queue_from_error(record_not_found_error, *delivery_event_args)
    # Only enqueue for ActiveRecord::RecordNotFound errors that were raised
    # when looking up a single record by ID.
    raise record_not_found_error unless record_not_found_error.is_a?(ActiveRecord::RecordNotFound) && record_not_found_error.id.is_a?(Numeric)

    model_name, id = record_not_found_error.model, record_not_found_error.id

    HookDeliveryRaceConditionCheckJob.set(wait: 30.seconds).perform_later(model_name, id, delivery_event_args)
  end

  def perform(model_name, id, delivery_event_args)
    ActiveRecord::Base.connected_to(role: :reading) { check_race_condition(model_name, id, delivery_event_args) }
  end

  def check_race_condition(model_name, id, delivery_event_args)
    model_class = model_name.constantize
    exists = model_class.exists?(id)
    # If a model doesn't exist we're dropping the event, so we want to track this.
    GitHub.dogstats.increment("hooks.delivery_race_condition.exists", tags: ["model:#{model_name}", "exists:#{exists}", "event_type:#{delivery_event_args.first}"])
    return unless exists

    # Record now exists in the database. This is likely a symptom of a race-condition
    # between the delivery job being picked up and the record being committed to the DB.
    #
    # This is a bug so we log event details and report it to our stats client
    event_type = delivery_event_args.first
    event = Hook::Event.for_event_type(event_type, delivery_event_args[1])
    action = event.respond_to?(:action) ? event.action : nil
    tags = GitHub::TaggingHelper.create_hook_event_tags(event_type, action)

    GitHub::logger.warn(
      "hook_delivery_race_condition",
      "code.namespace" => model_name,
      "gh.webhook.id" => id,
      "gh.webhook.event_type" => event_type,
      "gh.webhook.action" => action
    )

    # Set a race_condition flag to indicate that we shouldn't re-enqueue this event if we get an ActiveRecord::RecordNotFound error again.
    delivery_event_args[1]["race_condition"] = true
    DeliverHookEventJob.perform_later(*delivery_event_args)

    GitHub.dogstats.increment("hooks.delivery_race_condition", tags: tags)
  end
end
