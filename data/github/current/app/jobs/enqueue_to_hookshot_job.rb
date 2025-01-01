# typed: true
# frozen_string_literal: true

class EnqueueToHookshotJob < ApplicationJob
  queue_as :enqueue_to_hookshot

  retry_on_dirty_exit

  retry_on(Exception, wait: :polynomially_longer, attempts: 5)

  def serialize
    super.merge("delivered_hook_ids" => Array(@delivered_hook_ids))
  end

  def deserialize(arguments)
    @delivered_hook_ids ||= arguments["delivered_hook_ids"]
    super
  end

  def perform(payload, options = {})
    # round-trip through JSON to get string keys only
    payload = GitHub::JSON.parse(GitHub::JSON.encode(payload))
    @delivered_hook_ids ||= []
    tag_set = []
    GitHub.tracer.in_span("job.#{self.queue_name}.perform", kind: :internal, attributes: { "gh.webhook.component" => "jobs" }) do |_span|
      Array(payload["hooks"]).each do |hook_config|
        next if @delivered_hook_ids.include?(hook_config["id"])
        hook_payload = payload.dup.tap do |hash|
          hash["hook"] = hook_config
          hash.delete("hooks")
        end
        Hook::DeliverySystem.enqueue_payload_to_hookshot(hook_payload)
        GitHub.dogstats.increment("hooks.delivered_to_aqueduct.per_trigger.count", tags: tags(payload, :success))
        @delivered_hook_ids << hook_config["id"]
      end
    end
  rescue StandardError => e # rubocop:todo Lint/GenericRescue
    tag_set = tags(payload, :failure, e)
    GitHub.dogstats.increment("hooks.delivered_to_aqueduct.per_trigger.count", tags: tag_set)
    GitHub.dogstats.increment("hooks.hook_event_job.error", tags: tag_set)
    raise e
  end

  private

  def tags(payload, reason, exception = nil)
    action = payload.dig("payload", "action")
    event_type = payload["event"]
    default_tags = GitHub::TaggingHelper.create_hook_event_tags(event_type, action)
    default_tags << "type:pre_hydrated"
    default_tags << "status:#{reason}"
    default_tags << "site:#{GitHub.site}"
    default_tags << "class:#{self.class.name&.underscore}"
    default_tags << "queue:#{self.queue_name}"

    if reason == :failure
      default_tags << "exception_class:#{exception.class.name.underscore}"
    end

    default_tags
  end
end
