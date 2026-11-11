# typed: true
# frozen_string_literal: true

module Hookshot
  module DeliverJobLogger
    include Kernel

    def log_payload_too_large_error(error:, target: nil, parent: nil, event: nil, guid: nil, hook_ids: nil, push_sha: nil, **kwargs)
      unless error.is_a?(PayloadTooLarge)
        raise TypeError, "error is a #{error.class.name}, but expected Hookshot::PayloadTooLarge"
      end

      base_info = {
        "gh.webhook.is_enterprise" => GitHub.enterprise?,
        "gh.job.name" => self.to_s,
        "exception.type" => error.class.to_s,
        "gh.webhook.payload_size" => error.size
      }

      target_info = case target
      when Repository
        {
          "gh.repo.id" => target.id,
          "gh.repo.name_with_owner" => target.nwo,
        }
      when Organization
        {
          "gh.org.id" => target.id,
          "gh.org.name" => target.name,
        }
      else
        {}
      end

      arg_info = {
        "gh.webhook.push_sha" => push_sha,
        "gh.webhook.parent" => parent,
        "gh.webhook.delivery_guid" => guid,
        "gh.webhook.event_type" => event,
        "gh.webhook.hook_ids" => hook_ids,
      }

      payload_info = Hash[["gh.webhook.parent", "gh.webhook.delivery_guid", "gh.webhook.event_type"].zip error.payload.slice(:parent, :guid, :event).values]
      if hooks = error.payload[:hooks]
        payload_info["gh.webhook.hook_ids"] = error.payload[:hooks].map { |hook| hook[:id] }.join(",")
      end

      payload_info = arg_info.inject({}) do |hash, item|
        key, value = item
        hash.merge! key => (value || payload_info[key])
      end

      info = {}
      arg_info.each { |k, v| info[k] = (v || payload_info[k]) }

      log_info = base_info.merge(target_info).merge(info)
      GitHub::logger.warn("payload_too_large", log_info)
    end

    def log_no_method_error(error, event_type, action)
      unless error.is_a?(NoMethodError)
        raise TypeError, "error is a #{error.class.name}, but expected NoMethodError"
      end

      log_ctx = {
        "gh.catalog_service" => "github/webhooks",
        "gh.request_id" => GitHub.context[:request_id],
        "gh.webhook.event_type" => event_type,
        "gh.webhook.action" => action,
        "gh.job.name" => self.to_s,
        "exception.type" => error.class.to_s,
      }

      GitHub::logger.warn(log_ctx)
    end

    def instrument_event_metadata(event, filtered_reason:)
      GlobalInstrumenter.instrument("webhook.dropped_event_metadata", {
        event_type: event.event_type,
        event_action: event.attributes[:action],
        filtered_reason: filtered_reason,
        guid: event.guid,
        target_repository_id: event.repository_id || event.target_repository&.id,
        target_organization_id: event.organization_id || event.target_organization&.id,
        triggered_at:  event.attributes[:triggered_at],
        request_id: GitHub.context[:request_id]
      })
    end

    def report_error(error, opts = {})
      Failbot.report(error,
        app: "github-event-dispatch",
        **opts
      )
    end
  end
end
