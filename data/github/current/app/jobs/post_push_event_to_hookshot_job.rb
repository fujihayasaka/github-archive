# typed: true
# frozen_string_literal: true

class PostPushEventToHookshotJob < ApplicationJob
  include Hookshot::DeliverJobLogger

  class PayloadTooLarge < Hookshot::HookshotError; end
  PAYLOAD_TOO_LARGE_MSG = "Payload size of %s exceeds limit: %s, will not be delivered to Hookshot.".freeze

  queue_as :post_push_event_to_hookshot

  discard_on ActiveRecord::RecordNotFound

  RETRYABLE_ERRORS = [
    Errno::ECONNREFUSED,
    Errno::ECONNRESET,
    Errno::ETIMEDOUT,
    Faraday::ConnectionFailed,
    Faraday::TimeoutError,
    Net::HTTPRequestTimeOut,
    Net::ReadTimeout,
    GitRPC::CommandBusy,
    Aqueduct::Client::RequestError,
  ].freeze

  retry_on(*RETRYABLE_ERRORS, wait: :polynomially_longer, attempts: 5)
  retry_on_dirty_exit

  def self.job_name_for_tracing
    "post_push_event_to_hookshot"
  end

  def perform(delivery_payloads, options = {})
    GitHub.tracer.in_span("jobs.#{self.class.job_name_for_tracing}", kind: :internal, attributes: { "gh.webhook.component" => "jobs" }) do |_span|
      delivery_payloads.map! { |payload| payload.symbolize_keys }
      undelivered_payloads = delivery_payloads.reject { |payload| payload[:delivered] }

      tags = T.let([], T::Array[String])
      tags << "class:#{T.must(self.class.name).underscore}"
      undelivered_payloads.each do |delivery_payload|
        begin
          tags = tags + GitHub::TaggingHelper.create_hook_event_tags("push")
          payload = enrich_payload(delivery_payload, merge: options[:merge])

          if payload_fits_in_aqueduct?(payload)
            delivery_payload[:delivered_hook_ids] ||= []
            payload[:hooks].each do |hook_config|
              hook_config = hook_config.symbolize_keys
              next if delivery_payload[:delivered_hook_ids].include?(hook_config[:id].to_i)
              hook_payload = payload.dup.tap do |hash|
                hash[:hook] = hook_config
                hash.delete(:hooks)
                hash.delete(:delivered_hook_ids)
              end

              Hook::DeliverySystem.enqueue_payload_to_hookshot(hook_payload)

              delivery_payload[:delivered_hook_ids] << hook_config[:id].to_i
            end
          else
            Hook::DeliverySystem.post_payload_to_hookshot(payload)
            delivery_payload[:delivered] = true
          end
        rescue Hookshot::PayloadTooLarge => e
          # These errors are unexpected, since we should detect large payloads prior to submitting to hookshot-go
          # and not attempt to post the push event.

          extra_context = {
            push_sha: delivery_payload[:payload][:after],
            parent: delivery_payload[:parent],
            guid: delivery_payload[:guid],
            event: delivery_payload[:event],
            hook_ids: delivery_payload[:hooks].map { |hook| hook[:id] || hook["id"] },
            repo_id: delivery_payload.dig(:payload, :repository, :id),
            org_id: delivery_payload.dig(:payload, :organization, :id),
            user_id: delivery_payload.dig(:payload, :sender, :id),
          }

          tags << "exception_class:#{T.must(e.class.name).underscore}"
          log_payload_too_large_error(error: e, **extra_context)
          report_error(e, extra_context.transform_keys { |k| "##{k}" })
          GitHub.dogstats.increment("hooks.hook_event_job.error", tags: tags)
        rescue PayloadTooLarge => e
          # It's expected to see some payloads that are too large, so we won't report them to Sentry.
          GitHub::logger.error({
            :exception => e,
            "gh.webhook.push_sha" => delivery_payload[:payload][:after],
            "gh.webhook.parent" => delivery_payload[:parent],
            "gh.webhook.delivery_guid" => delivery_payload[:guid],
            "gh.webhook.event_type" => delivery_payload[:event],
            "gh.webhooks" => delivery_payload[:hooks].map { |hook| hook[:id] || hook["id"] },
            "gh.repo.id" => delivery_payload.dig(:payload, :repository, :id),
            "gh.org.id" => delivery_payload.dig(:payload, :organization, :id),
            "gh.user.id" => delivery_payload.dig(:payload, :sender, :id)
          })
        rescue StandardError => e # rubocop:todo Lint/GenericRescue
          # add this rescue so we can count unknown exceptions and where they come from
          tags << "exception_class:#{T.must(e.class.name).underscore}"
          GitHub.dogstats.increment("hooks.hook_event_job.error", tags: tags)
          raise e
        end
      end
    end
  end

  def enrich_payload(delivery_payload, merge: false)
    GitHub.tracer.in_span("jobs.#{self.class.job_name_for_tracing}.enrich", kind: :internal, attributes: get_trace_attributes(delivery_payload)) do |_span|
      webhook_payload = delivery_payload[:payload]

      # Every payload sent to this job has the same `webhook_payload`. Thus we
      # can cache the event between payloads.
      #
      GitHub.tracer.in_span("jobs.#{self.class.job_name_for_tracing}.repo_find", kind: :internal, attributes: get_trace_attributes(delivery_payload)) do |_span|
        @repo ||= ActiveRecord::Base.connected_to(role: :reading) do
          Repositories::Public.get_active_or_deleted!(webhook_payload.dig(:repository, :id))
        end
      end
      @event ||= begin
        event_attrs = {
          repo: @repo,
          before: webhook_payload[:before],
          after: webhook_payload[:after],
          ref: webhook_payload[:ref],
        }

        Hook::Event::PushEvent.new(event_attrs)
      end

      # Special case for Actions and Chatops which wants a smaller payload As explained above
      # we can cache both sets of git data as they are the same between payloads.
      if use_actions_push_payload?(delivery_payload, @repo) || use_chatops_push_payload?(delivery_payload)
        GitHub.tracer.in_span("jobs.#{self.class.job_name_for_tracing}.actions_payload", kind: :internal, attributes: get_trace_attributes(delivery_payload)) do |_span|
          payload_generator = Hook::Payload::ActionsPushPayload.new(@event, include_git_data: true, merge: merge)
          @slim_data ||= payload_generator.git_only
          delivery_payload[:payload] = delivery_payload[:payload].merge(@slim_data)
        end
      else
        GitHub.tracer.in_span("jobs.#{self.class.job_name_for_tracing}.push_payload", kind: :internal, attributes: get_trace_attributes(delivery_payload)) do |_span|
          payload_generator = Hook::Payload::PushPayload.new(@event, include_git_data: true, merge: merge)
          @full_data ||= payload_generator.git_only
          delivery_payload[:payload] = delivery_payload[:payload].merge(@full_data)
        end
      end

      check_payload_size!(delivery_payload)
    end
    delivery_payload
  end

  def get_trace_attributes(payload)
    {
      "gh.webhook.component" => "jobs",
      "gh.webhook.event" => "push",
      "gh.request_id" => payload[:github_request_id] || "",
      "gh.webhook.push_sha" => payload.dig(:payload, :after) || "",
      "gh.webhook.parent" => payload[:parent] || "" ,
      "gh.webhook.delivery_guid" => payload[:guid] || "",
    }
  end

  def check_payload_size!(payload)
    payload_size = payload.to_json.bytesize

    tags = GitHub::TaggingHelper.create_hook_event_tags("push")
    tags += ["is_large_aqueduct_payload:#{GitHub::Aqueduct.is_payload_size_large?(payload_size)}"]
    GitHub.dogstats.distribution("hooks.hookshot_payload.payload_size", payload_size, tags: tags)

    if payload_size > GitHub.hookshot_payload_size_limit
      payload[:hooks].each do
        GitHub.dogstats.distribution("hooks.hookshot_payload.payload_too_large", payload_size, tags: tags)
      end

      raise PayloadTooLarge, (PAYLOAD_TOO_LARGE_MSG % [payload_size, GitHub.hookshot_payload_size_limit])
    end
  end

  def use_actions_push_payload?(delivery_payload, repo)
    return true if delivery_payload[:parent] == "integration-#{GitHub.launch_github_app&.id}"
    GitHub.flipper[:use_actions_push_payload].enabled?(repo)
  end

  def use_chatops_push_payload?(delivery_payload)
    Hook::DeliverySystem.is_chatops_integration_prod_delivery?(delivery_payload[:parent])
  end

  def payload_fits_in_aqueduct?(payload)
    !GitHub::Aqueduct.is_payload_size_large?(payload.to_json.bytesize)
  end
end
