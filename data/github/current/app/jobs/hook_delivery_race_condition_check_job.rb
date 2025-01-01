# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class HookDeliveryRaceConditionCheckJob < ApplicationJob
  default_to_write_connection! # rubocop:todo GitHub/JobsDoNotDefaultToWriteConnection

  queue_as :hook_delivery_race_condition_check

  retry_on StandardError, wait: :polynomially_longer

  retry_on_dirty_exit

  def self.extract_model_and_id_from_exception(record_not_found_error)
    if /\ACouldn't find ([\w:]+) with '?ID'?=(\d+)\z/i =~ record_not_found_error.message
      [$1, $2.to_i]
    end
  end

  def self.queue_from_error(record_not_found_error, *delivery_event_args)
    model_name, id = extract_model_and_id_from_exception(record_not_found_error)

    # Only retry cases where we were explicitly finding by ID.
    raise record_not_found_error unless model_name && id

    HookDeliveryRaceConditionCheckJob.set(wait: 30.seconds).perform_later(model_name, id, delivery_event_args)
  end

  def perform(model_name, id, delivery_event_args)
    if GitHub.flipper[:webhooks_race_condition_job_read_from_replica].enabled?
      ActiveRecord::Base.connected_to(role: :reading) { check_race_condition(model_name, id, delivery_event_args) }
    else
      check_race_condition(model_name, id, delivery_event_args)
    end
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
    delivery_event_args[1]["race_condition"] = true if GitHub.flipper[:webhooks_race_condition_flag].enabled?
    DeliverHookEventJob.perform_later(*delivery_event_args)

    GitHub.dogstats.increment("hooks.delivery_race_condition", tags: tags)
  end
end
