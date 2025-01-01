# typed: true
# frozen_string_literal: true

require "instrumentation/attachable_subscriber"

module InstrumentationSubscribers
  class Hook
    include Instrumentation::AttachableSubscriber

    set_attachable_namespace :hook

    # Emitted when a Hook has been delivered.
    handle_event :response

    private

    def hook_timing(started, payload)
      delivery = payload[:delivery]
      (started.to_f * 1000).round - delivery.created_ms.to_i
    end

    def handle_in_development(action, started, ended, id, payload)
      hook = payload[:hook]
      ms = hook_timing(started, payload)
      Rails.logger.warn "#{hook.name} Hook: #{ms}ms"
    end

    def handle_in_production(action, started, ended, id, payload)
      ms = hook_timing(started, payload)
      GitHub.dogstats.timing(payload[:sender], ms, tags: ["action:delivery"])
    end
  end
end
