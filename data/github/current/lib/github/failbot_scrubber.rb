# typed: true
# frozen_string_literal: true

module GitHub
  class FailbotScrubber
    # Be very careful adding keys here! They will be totally ignored by the scrubber
    # This is reserved for keys that'd be over-aggressively filtered otherwise
    SKIPPED_KEYS = [
      "backtrace", # can include lines like the rails key
      "kube_pod_ip", # Internal pod IP
      "rails", # ie 6.0.2.1.1eb7ba796d
      "exception_detail", # handled by scrub_exception_detail
      "user_agent", # this was observed to fail sometimes in production. it's not sensitive anyways

      # internal use: add these to the context before we iterate on them
      "failbot_scrub_failed_on_keys",
      "failbot_scrub_failed",
    ].to_set

    def initialize(enabled:)
      @enabled = enabled
    end

    def call(context, sensitive_context, thread)
      return unless @enabled

      scrubbed_keys = []
      context["#failbot_scrub_failed"] = nil
      context["failbot_scrub_failed_on_keys"] = []

      scrub_exception_detail(context, sensitive_context, scrubbed_keys, thread)

      context.each do |key, value|
        begin
          key = key.delete_prefix("#") # take into account key being a tag
          next if SKIPPED_KEYS.include?(key)
          next if SensitiveData.safe_input?(value)

          scrub(value, thread) do |scrubbed|
            sensitive_context[key] = value
            context[key] = scrubbed
            scrubbed_keys.push(key)
          end
        rescue StandardError => e # rubocop:todo Lint/RescueException
          context["#failbot_scrub_failed"] = true
          context["failbot_scrub_failed_on_keys"].push(key)
        end
      end

      context["#failbot_scrubbed_any"] = scrubbed_keys.any?
      context["failbot_scrubbed_keys"] = scrubbed_keys
      context["#failbot_scrub_failed"] = context["failbot_scrub_failed_on_keys"].any?
    rescue StandardError => e # rubocop:todo Lint/RescueException
      context["#failbot_scrub_failed"] = true
      context["#failbot_scrubbed_any"] = false if context["#failbot_scrubbed_any"].nil?
    end

    private

    # Scrub a value.  Yields the scrubbed value to the optional block if
    # scrubbing had any effect.
    def scrub(value, thread)
      stringified_value = SensitiveData.coerce_to_string(value)
      scrubbed_value = SensitiveData.scrub(stringified_value, thread)

      if stringified_value != scrubbed_value && block_given?
        yield scrubbed_value
      end

      scrubbed_value
    end

    # The exception_detail field needs special handling since it must retain
    # its structure.  Exception#message lives in
    # context["exception_detail"][\d]["value"], that is the only part that needs scrubbed
    def scrub_exception_detail(context, sensitive_context, scrubbed_keys, thread)
      if context["exception_detail"]
        context["exception_detail"].each_with_index do |detail, idx|
          if detail["value"]
            scrub(detail["value"], thread) do |scrubbed|
              sensitive_context["exception_detail.#{idx}.value"] = detail["value"]
              context["exception_detail"][idx]["value"] = scrubbed
              scrubbed_keys.push("exception_detail.#{idx}.value")
            end
          end
        end
      end
    rescue StandardError => e # rubocop:todo Lint/RescueException
      context["#failbot_scrub_failed"] = true
      context["failbot_scrub_failed_on_keys"].push("exception_detail")
    end
  end
end
