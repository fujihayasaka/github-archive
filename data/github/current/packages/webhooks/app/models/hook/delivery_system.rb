# typed: true
# frozen_string_literal: true

class Hook::DeliverySystem
  class PayloadsNotGenerated < StandardError; end
  class PayloadTooLarge < Hookshot::HookshotError; end
  include Hook::ActionsDependency
  include Hookshot::DeliverJobLogger
  extend Hookshot::DeliverJobLogger

  # DeliverySystem is a quagmire in which it can be easy to get lost. Here are
  # some notes to help you find your way.
  #
  # There are 4 main entry points into DeliverySystem:
  # 1) `deliver` - called from the `DeliverHookEvent` background job via
  # `HookEventSubscriber` instrumentation. Generates webhook payloads then
  # sends them off for delivery.
  #
  # 2) `deliver_later` - called in model instrumentation. Webhook payload must
  # be pre-generated. POSTs directly to hookshot or triggers `EnqueueToHookshotJob`
  # based on size of payload.
  #
  # 3) `deliver_push_event_later` - specifically for Push events. Triggers
  # `PostPushEventToHookshotJob`. Webhook payload must be pre-generated, but
  # git data is added in `PostPushEventHookEventJob`.
  #
  # 4) `redeliver` - for redeliveries. Payload is retried from the database
  # within Hookshot.

  DELIVERY_QUEUE = "hookshot"
  REDELIVERY_QUEUE = "hookshot-redeliveries"

  ACTIONS_SERVICE = "actions"
  CHATOPS_SERVICE = "chatops"
  HOOKSHOT_SERVICE = "hookshot"

  # hookshot-go has the following flow:
  # - Receive job from Aqueduct (up to 20s)
  # - Deliver hook (up to 10s)
  # - Ack job to Aqueduct (up to 20s)
  # We add 10s of padding just in case to get 60s before Aqueduct retries
  # a job if it has not received an ack from hookshot-go.
  AQUEDUCT_UNACKED_REDELIVERY_TIMEOUT = 60

  def log_context
    @log_context ||= {
      file: "packages/webhooks/app/models/hook/delivery_system.rb",
      catalog_service: "github/webhooks",
      request_id: GitHub.context[:request_id],
      event: hook_event.event_type,
      action: hook_event.try(:action)
    }
  end

  # Public: Iterates over available features for a given parent
  #
  # parent - The model of the hook
  #
  # Returns string Array
  def self.feature_flags_for_payload(parent)
    return [] unless parent.is_a?(String)

    [].tap do |features_array|
      if GitHub.flipper[:write_to_hookshot_resharded_db].enabled?(Hook::ParentAsActor.new(parent))
        features_array << :write_to_hookshot_resharded_db
      end
      if GitHub.flipper[:hookshot_go_async_hook_delivery_metadata].enabled?(Hook::ParentAsActor.new(parent))
        features_array << :hookshot_go_async_hook_delivery_metadata
      end
      if GitHub.flipper[:hookshot_go_async_hook_delivery_payloads].enabled?(Hook::ParentAsActor.new(parent))
        features_array << :hookshot_go_async_hook_delivery_payloads
      end
      if GitHub.flipper[:webhooks_validate_payload_schema].enabled?(Hook::ParentAsActor.new(parent))
        features_array << :webhooks_validate_payload_schema
      end
    end
  end

  # Public: Instantiates a delivery system instance for the specified hook event
  # and then triggers a delivery.
  #
  # hook_event - The Hook::Event to be delivered.
  #
  # Returns nothing.
  def self.deliver(hook_event)
    new(hook_event).deliver
  end

  # Public: Redelivers the specified past delivery for a given Hook.
  #
  # delivery_guid - The GUID string of the past delivery.
  # hook - The Hook which the redelivery should target.
  #
  # Returns true.
  def self.redeliver(delivery_guid, hook)
    payload = {
      hook_id: hook.id,
      guid: delivery_guid,
      parent: hook.hookshot_parent_id,
      hook_data: hook.config_with_tenant_scoped_url,
      hook_configuration: {
        needs_public_key_signature: needs_public_key_signature?(hook)
      }
    }

    # no large payloads here because we get the full payload out of the DB in
    # hookshot-go, so no need to have logic for enqueueing to Aqueduct vs.
    # POSTing to Hookshot
    post_redelivery_to_aqueduct(payload)

    true
  end

  # Public: pushes a payload to Hookshot.
  #
  # payload - The Hash payload that should be POSTed to Hookshot
  #
  # Used only for payloads > 5MB
  #
  # Returns nothing.
  def self.post_payload_to_hookshot(payload)
    parent = (payload[:parent] || payload["parent"])
    hookshot_client = Hookshot::Client.for_parent(parent)
    GitHub.tracer.in_span("delivery_system.post_payload_to_hookshot", kind: :internal, attributes: get_attribute_tags(payload, parent)) do |_span|
      status, body = time_and_log_request("hooks.send_to_hookshot.time", payload) do
        hookshot_client.deliver(payload)
      end

      tags = GitHub::TaggingHelper.create_hook_event_tags(payload.dig(:event), payload.dig(:payload, :action))
      tags << "queue:none"
      num_hooks = (payload[:hooks] || payload["hooks"]).count
      GitHub.dogstats.count("hooks.delivered_to_queue.per_hook.count", num_hooks,  tags: tags) if status == 200
      raise Hookshot::PayloadTooLarge.new(payload, payload.to_json(dangerously_allow_all_keys: true).bytesize) if status == 413
      raise Hookshot::BadResponseError.new(status, body) unless status == 200
    end
  end

  # Public: enqueues a payload with the queueing system (Hookshot Aqueduct queues or
  # Actions' Aqueduct queues for GitHub Actions events or ChatOps aqueduct queues for Github Chatops integrations: msteams.rb/slack.rb)
  #
  # payload - The Hash payload that should be enqueued
  #
  # Returns nothing
  def self.enqueue_payload_to_hookshot(payload, hook = nil)
    # Queue determinator based on url will be added here
    payload = payload.with_indifferent_access
    parent = hook&.hookshot_parent_id || payload[:parent]
    payload = augment_payload(payload)
    queue = T.let(nil, T.nilable(String))
    service = T.let(nil, T.nilable(String))

    tags = GitHub::TaggingHelper.create_hook_event_tags(payload.dig("event"), payload.dig("payload", "action"))
    GitHub.tracer.in_span("delivery_system.enqueue_payload_to_hookshot", kind: :internal, attributes: get_attribute_tags(payload, parent)) do |_span|

      if is_actions_delivery?(parent) # Webhooks for GitHub Actions are delivered via its own aqueduct queue
        if payload[:payload].present? && payload[:payload].has_key?("actions_meta")
          payload[:actions_meta] = payload[:payload][:actions_meta]
          payload[:payload].delete("actions_meta")
        end
        queue = actions_queue_for(parent)
        service = ACTIONS_SERVICE
        job_args = build_aqueduct_job(payload, queue)
        Hook::ActionsDependency.add_ttl_to_aqueduct_job_args(job_args, payload, queue)

        actions_aqueduct_client.send_job(**job_args)
      elsif is_chatops_integration_delivery?(parent)
        # Webhooks for ChatOps Integrations(slack & msteams) are delivered via its own aqueduct queue
        queue = chatops_queue_for(parent, payload[:event])
        service = CHATOPS_SERVICE
        job_args = build_aqueduct_job(payload, queue)
        chatops_aqueduct_client.send_job(**job_args)
      else
        payload[:payload].delete("actions_meta") if payload[:payload].present?
        queue = DELIVERY_QUEUE
        service = HOOKSHOT_SERVICE
        job_args = build_aqueduct_job(payload, DELIVERY_QUEUE)
        client = aqueduct_client_for(parent)
        aqueduct_app = aqueduct_app_for(parent)
        tags << "aqueduct_app:#{aqueduct_app}"
        client.send_job(**job_args)
      end
      tags = tags + ["queue:#{queue}", "service:#{service}"]
      GitHub.dogstats.increment("hooks.delivered_to_queue.per_queue.count", tags: tags)

      if GitHub.multi_tenant_enterprise? && GitHub.flipper[:tenant_context_telemetry_webhooks_dd].enabled?
        tenant_headers_present = "false"
        if payload["hook"]["headers"].present?
          if payload["hook"]["headers"].any? { |header| header.has_key?("X-GitHub-Tenant") }
            tenant_headers_present = "true"
          end
        end

        tags = tags + GitHub::CurrentTenant.metrics_tags + ["tenant_headers_present:#{tenant_headers_present}"]
        GitHub.dogstats.increment("tenant_context.webhooks", tags: tags)
      end

      begin
        start_time = SimpleUUID::UUID.new(payload[:guid]).to_time
        webhook_latency = GitHub::Dogstats.duration(start_time)
        GitHub.dogstats.distribution("hooks.webhook_latency", webhook_latency, tags: tags)
      rescue TypeError => e
        report_error(e)
      end
    end
  end

  def self.get_attribute_tags(payload, parent = nil)
    {
      "gh.webhook.parent" => parent || "",
      "gh.webhook.is_actions" => is_actions_delivery?(parent),
      "gh.webhook.is_chatops_integration" => is_chatops_integration_delivery?(parent),
      "gh.webhook.id" => payload.dig(:hook, :id) || "",
      "gh.webhook.delivery_guid" => payload[:guid] || "",
      "gh.request_id" => payload[:github_request_id] || "",
      "gh.webhook.event" => payload[:event] || "",
      "gh.webhook.action" => payload.dig(:payload, :action).to_s,
    }
  end

  def self.is_actions_delivery?(parent)
    Hook::ActionsDependency.is_actions_delivery?(parent)
  end

  def is_actions_delivery?(parent)
    self.class.is_actions_delivery?(parent)
  end

  def self.is_actions_prod_delivery?(parent)
    Hook::ActionsDependency.is_actions_prod_delivery?(parent)
  end

  def is_actions_prod_delivery?(parent)
    self.class.is_actions_prod_delivery?(parent)
  end

  def self.is_actions_lab_delivery?(parent)
    Hook::ActionsDependency.is_actions_lab_delivery?(parent)
  end

  def is_actions_lab_delivery?(parent)
    self.class.is_actions_lab_delivery?(parent)
  end

  def self.actions_queue_for(parent)
    Hook::ActionsDependency.actions_queue_for(parent)
  end

  def self.chatops_queue_for(parent, event_type)
    return nil unless is_chatops_integration_delivery?(parent)
    # separate queues for workflow_run and workflow_job event types
    return "#{chatops_client_queue_for(parent)}-workflows" if %w[workflow_run workflow_job].include?(event_type)
    chatops_client_queue_for(parent)
  end

  def self.chatops_client_queue_for(parent)
    return "webhook-slack" if parent == "integration-#{GitHub.slack_github_app&.id}"
    return "webhook-teams" if parent == "integration-#{GitHub.msteams_github_app&.id}"
    nil
  end

  def self.is_chatops_integration_delivery?(parent)
    return false unless is_chatops_integration_prod_delivery?(parent)
    true
  end

  def self.is_chatops_integration_prod_delivery?(parent)
    parent == "integration-#{GitHub.slack_github_app&.id}" || parent == "integration-#{GitHub.msteams_github_app&.id}"
  end

  def self.build_aqueduct_job(payload, queue)
    carrier = GitHub.context_propagation_map
    headers = {}.merge(carrier)

    if GitHub.multi_tenant_enterprise? && (tenant = GitHub::CurrentTenant.get)
      headers.merge!(
        "X-GitHub-Tenant" => tenant.slug,
        "X-GitHub-Tenant-ID" => tenant.id.to_s,
      )
    end

    {
      queue: queue,
      payload: payload.to_json(dangerously_allow_all_keys: true),
      headers: headers,
      redelivery_timeout_secs: AQUEDUCT_UNACKED_REDELIVERY_TIMEOUT,
    }
  end

  def self.aqueduct_client_for(parent)
    if Hookshot::Client::PARENTS_USING_STAGING.key?(parent) || GitHub.dynamic_lab?
      self.hookshot_go_staging_aqueduct_client
    else
      self.hookshot_go_default_aqueduct_client
    end
  end

  def self.aqueduct_app_for(parent)
    if Hookshot::Client::PARENTS_USING_STAGING.key?(parent) || GitHub.dynamic_lab?
      "hookshot-staging"
    else
      "hookshot-#{Rails.env}"
    end
  end

  def self.chatops_aqueduct_client
    @chatops_aqueduct_client ||= GitHub.build_aqueduct_client(
      app: "chatops-#{Rails.env}",
      url: GitHub.aqueduct_gateway_url,
      circuit_breaker: GitHub.aqueduct_gateway_circuit_breaker,
      api_key: GitHub.aqueduct_chatops_api_key,
      api_key_version: GitHub.aqueduct_chatops_api_key_version,
    )
  end

  def self.actions_aqueduct_client
    GitHub.build_aqueduct_client(
      app: "actions-#{Rails.env}",
      url: GitHub.aqueduct_gateway_url,
      circuit_breaker: GitHub.aqueduct_gateway_circuit_breaker,
      api_key: GitHub.aqueduct_actions_api_key,
      api_key_version: GitHub.aqueduct_actions_api_key_version,
    )
  end

  def self.hookshot_go_staging_aqueduct_client
    @hookshot_go_staging_aqueduct_client ||= GitHub.build_aqueduct_client(
      app: "hookshot-staging",
      url: GitHub.aqueduct_hookshot_staging_url,
      circuit_breaker: GitHub.aqueduct_gateway_circuit_breaker,
      api_key: GitHub.aqueduct_hookshot_staging_api_key,
      api_key_version: GitHub.aqueduct_hookshot_staging_api_key_version,
    )
  end

  def self.hookshot_go_default_aqueduct_client
    @hookshot_go_default_aqueduct_client ||= GitHub.build_aqueduct_client(
      app: "hookshot-#{Rails.env}",
      url: GitHub.aqueduct_hookshot_url,
      circuit_breaker: GitHub.aqueduct_gateway_circuit_breaker,
      api_key: GitHub.aqueduct_hookshot_api_key,
      api_key_version: GitHub.aqueduct_hookshot_api_key_version,
    )
  end

  # Enqueues a redelivery in the queueing system (Aqueduct)
  def self.post_redelivery_to_aqueduct(redelivery_payload)
    GitHub.dogstats.distribution_time("hooks.send_redelivery_to_aqueduct.time") do
      begin
        redelivery_payload = redelivery_payload.with_indifferent_access
        redelivery_payload = augment_payload(redelivery_payload)

        job_args = build_aqueduct_job(redelivery_payload, REDELIVERY_QUEUE)
        client = aqueduct_client_for(redelivery_payload[:parent])
        client.send_job(**job_args)
      rescue Aqueduct::Client::ClientError => e
        GitHub.dogstats.increment("hooks.send_redelivery_to_aqueduct.error")
        raise e
      end
    end
  end

  attr_reader :hook_event

  def initialize(hook_event)
    @hook_event = hook_event
  end

  # Public: Called by DeliverHookEventJob. Enqueues the event payload for
  # delivery.
  #
  # Called by DeliverHookEventJob via hook event subscriptions
  # (`HookEventSubscriber`). This method is used when the payload can be
  # hydrated after the action has happened. Hook payloads are generated in
  # this method, whereas for `deliver_later` the payload must be
  # pre-generated.
  #
  # If the payload is too big, sends it directly to Hookshot via a POST.
  #
  # Otherwise, enqueues it in Aqueduct for consumption by hookshot or Actions
  # (logic for this is in `enqueue_payload_to_hookshot`)
  #
  # Records info about the delivery in Hydro for non-enterprise.
  #
  # Returns nothing.
  def deliver
    tags = GitHub::TaggingHelper.create_hook_event_tags(hook_event.event_type, hook_event.try(:action))
    tags << "type:jit_hydrated"
    tags << "site:#{GitHub.site}"

    begin
      metric_name = ""

      if should_generate_hookshot_payloads? && require_on_demand_actions_app_installation?
        install_actions_app_and_queue_event
      end


      generate_hookshot_payloads

      if @hookshot_deliveries.none?
        GitHub.dogstats.increment("hooks.no_deliveries.count", tags: tags)
        instrument_event_metadata(hook_event, filtered_reason: "no_deliveries")
        return
      end

      hook_metadata_size = 0

      @hookshot_deliveries.each do |delivery|
        if delivery.hookshot_payload.nil?
          next
        end

        hookshot_payload_size = delivery.hookshot_payload.to_json(dangerously_allow_all_keys: true).bytesize
        hook_metadata_size += hookshot_payload_size - delivery.payload_size

        if GitHub::Aqueduct.is_payload_size_large?(hookshot_payload_size)
          metric_name = "hooks.delivered_to_hookshot.per_trigger.count"
          self.class.post_payload_to_hookshot(delivery.hookshot_payload)
        else
          metric_name = "hooks.delivered_to_aqueduct.per_trigger.count"
          delivery.hooks.each do |hook|
            next if hook_event.attributes[:delivered_hook_ids].include?(hook.id)
            hook_config_hash = delivery.hookshot_payload[:hooks].find { |h| h[:id] == hook.id }
            payload = delivery.hookshot_payload.dup.tap do |hash|
              hash[:hook] = hook_config_hash
              hash.delete(:hooks)
            end

            self.class.enqueue_payload_to_hookshot(payload, hook)
            hook_event.attributes[:delivered_hook_ids] += [hook.id]
          end
        end

        instrument_delivery(delivery)
      end

      GitHub.dogstats.distribution("hooks.hook_metadata_size", hook_metadata_size, tags: tags)
      GitHub.dogstats.distribution("hooks.event_payload_size", @hookshot_deliveries.first.payload_size, tags: tags)

      tags << "status:success"

      GitHub.dogstats.increment(metric_name, tags: tags)
    rescue => e # rubocop:todo Lint/GenericRescue
      tags << "status:failure"
      tags << "exception_class:#{e.class.name&.underscore}"
      GitHub.dogstats.increment(metric_name, tags: tags)

      raise e
    end
  end

  # Public: Enqueues background jobs to deliver pre-generated push event
  # payloads.
  #
  # Push events are handled specially because they contain git data that is
  # expensive to generate; `PostPushEventToHookshotJob` caches some of this
  # across webhooks for efficiency.
  #
  # Because this delivery method pushes hook payloads into Redis to enqueue the
  # background job, it should be used with care to avoid a negative impact on
  # the amount of memory available to Redis.
  #
  #
  # Records info about the delivery in Hydro for non-enterprise.
  #
  # Returns nothing.
  def deliver_push_event_later(merge: false)
    unless @payloads_generated
      raise PayloadsNotGenerated, "you must call `generate_hookshot_payloads' " +
        "before calling `deliver_later'"
    end

    return if payloads.none?

    tags = GitHub::TaggingHelper.create_hook_event_tags(hook_event.event_type, hook_event.try(:action))
    tags << "site:#{GitHub.site}"
    attributes_size = hook_event.attributes.to_json(dangerously_allow_all_keys: true).bytesize
    payload_size = payloads.to_json(dangerously_allow_all_keys: true).bytesize
    # This is for tracking purposes to determine the size of tier1 events in the future Events V2 system.
    # tier1 events will include both the prehydrated payload and the attributes of the event.
    GitHub.dogstats.distribution("hooks.tier1_event_size", payload_size + attributes_size, tags: tags + ["prehydrated:true"])


    tags << "job:post-push-event-to-hookshot"
    PostPushEventToHookshotJob.perform_later(payloads, { merge: merge })

    @hookshot_deliveries.each do |delivery|
      instrument_delivery(delivery)
    end

    count = payloads.sum { |payload| payload[:hooks].count }
    GitHub.dogstats.count("hooks.enqueued_per_hook.count", count, tags: tags)
    GitHub.dogstats.increment("hooks.job_enqueued.count", tags: tags)
  end

  # Public: Enqueues background jobs to deliver pre-generated payloads.
  #
  # This method is used for events that need to skip over instrumentation because
  # they need the payload hydrated up front (i.e. deletes, where the mysql
  # record may no longer exist if the payload were hydrated in a background
  # job).
  #
  # Because this delivery method pushes hook payloads into Redis to enqueue the
  # background job, it should be used with care to avoid a negative impact on
  # the amount of memory available to Redis.
  #
  # If the payload is too big, sends it directly to Hookshot via a POST.
  #
  # Otherwise, enqueues it in Aqueduct (logic for this is in
  # `enqueue_payload_to_hookshot`)
  #
  # Records info about the delivery in Hydro for non-enterprise.
  #
  # Returns nothing.
  def deliver_later
    unless @payloads_generated
      raise PayloadsNotGenerated, "you must call `generate_hookshot_payloads' " +
        "before calling `deliver_later'"
    end

    return if payloads.none?
    return unless hook_event.feature_flag_enabled?

    attributes_size = hook_event.attributes.to_json(dangerously_allow_all_keys: true).bytesize

    tags = GitHub::TaggingHelper.create_hook_event_tags(hook_event.event_type, hook_event.try(:action))
    tags << "site:#{GitHub.site}"
    @hookshot_deliveries.each do |delivery|
      next if delivery.hookshot_payload.nil?
      payload_size = delivery.hookshot_payload.to_json(dangerously_allow_all_keys: true).bytesize

      # This is for tracking purposes to determine the size of tier1 events in the future Events V2 system.
      # tier1 events will include both the prehydrated payload and the attributes of the event.
      GitHub.dogstats.distribution("hooks.tier1_event_size", payload_size + attributes_size, tags: tags + ["prehydrated:true"])

      if GitHub::Aqueduct.is_payload_size_large?(payload_size)
        self.class.post_payload_to_hookshot(delivery.hookshot_payload)
        GitHub.dogstats.increment("hooks.delivered_to_hookshot.per_trigger.count", tags: tags)
      else
        EnqueueToHookshotJob.perform_later(delivery.hookshot_payload)
        metrics_tags = tags + ["job:enqueue-to-hookshot"]
        GitHub.dogstats.increment("hooks.enqueued_per_hook.count", tags: metrics_tags)
        GitHub.dogstats.increment("hooks.job_enqueued.count", tags: metrics_tags)
      end

      instrument_delivery(delivery)
    end
  end

  def payloads
    @hookshot_deliveries.map(&:hookshot_payload).compact
  end

  # Public: Generates the event/hook's payloads for Hookshot delivery. This
  # method is available to front-load payloads before #deliver_later is called.
  # For example, where we may simply call #deliver_later in an after_destroy, we
  # can instead call #generate_hookshot_payloads in a before_destroy and then
  # call #deliver_later in an after_commit, avoiding communication with Redis
  # during a MySQL transaction.
  #
  # Returns nothing.
  def generate_hookshot_payloads
    tags = GitHub::TaggingHelper.create_hook_event_tags(hook_event.event_type, hook_event.try(:action))
    tags << "operation:generate_hookshot_payloads"
    GitHub.dogstats.distribution_time("hooks.time", tags: tags) do
      log_context = self.log_context.merge({ fn: "DeliverySystem#generate_hookshot_payloads" })

      @hookshot_deliveries = []
      @payloads_generated = true

      return unless should_generate_hookshot_payloads?

      @hookshot_deliveries = deliveries
      deliveries.each do |delivery|
        begin
          next if delivery.hooks.none?
          payload = hookshot_payload(delivery)
          delivery.hookshot_payload = payload
        rescue PayloadTooLarge => e
          GitHub::logger.error({ :exception => e, "gh.webhook.delivery_guid" => hook_event.guid })
          report_error(e)
        end
      end
    end
  end

  # Public: Generates the event/hook's payloads for Hookshot delivery. This
  # method is available to front-load payloads before #deliver_later is called.
  # For example, where we may simply call #deliver_later in an after_destroy, we
  # can instead call #generate_hookshot_payloads in a before_destroy and then
  # call #deliver_later in an after_commit, avoiding communication with Redis
  # during a MySQL transaction.
  #
  # Returns nothing.
  def generate_push_event_hookshot_payloads
    if hook_event && !hook_event.is_a?(Hook::Event::PushEvent)
      raise "generate_push_event_hookshot_payloads cannot be called for any event other than a PushEvent"
    end
    # instantiate @deliveries while associated resources are still in the db
    @hookshot_deliveries = []
    @payloads_generated = true
    return if Rails.env.test? && !Hook.delivers_in_test?
    return unless hook_event.deliverable?
    return if hook_event.model_importing?
    return if hook_event.target_repository_disallows_hooks?

    tags = GitHub::TaggingHelper.create_hook_event_tags(hook_event.event_type, hook_event.try(:action))
    tags << "operation:generate_hookshot_payloads"
    GitHub.dogstats.distribution_time("hooks.time", tags: tags) do
      @hookshot_deliveries = deliveries
      deliveries.each do |delivery|
        next if delivery.hooks.none?
        payload = begin
          current_installation = installation_specifics_for(delivery.parent)

          webhook_payload = Hook::Payload::PushPayload.new(hook_event, include_git_data: false)

          delivery_rate_limit_key, pricing_plan = hook_event.delivery_rate_limit_data
          payload = {
            parent: delivery.parent,
            guid: delivery.guid,
            event: hook_event.event_type,
            payload: webhook_payload.to_hash.merge(current_installation),
            hooks: delivery.hooks.map do |hook|
              {
                  id: hook.id,
                  service: hook.name,
                  configuration: {
                    needs_public_key_signature: self.class.needs_public_key_signature?(hook),
                  },
                  headers: delivery.headers_for(hook),
                  data: hook.config,
                  callback_url: "#{GitHub.api_url}/hooks/#{delivery.guid}/#{hook.id}",
              }.tap do |hook_data|
                hook_data[:metadata] = {
                  repo_id: delivery&.target_repository&.id,
                  installation_id: current_installation.dig(:installation, :id),
                }
              end
            end,
            delivery_rate_limit_key: delivery_rate_limit_key,
            pricing_plan: pricing_plan,
          }
        end
        delivery.hookshot_payload = payload
      end
    end
  end

  # Builds a Hook::Delivery for each group of hooks. A deliveries hooks
  # must be for the same parent.
  #
  # Returns an array of Hook::Delivery objects
  def deliveries
    @deliveries ||= grouped_hooks.map do |parent, hooks|
      Hook::Delivery.new(hook_event, parent, hooks)
    end
  end

  def self.needs_public_key_signature?(hook)
    target = hook.installation_target

    if target.respond_to?(:flipper_id)
      GitHub.flipper[:public_key_webhook_signing].enabled?(target)
    else
      false
    end
  end

  def self.augment_payload(payload)
    payload.merge(
      github_request_id: GitHub.context[:request_id],
      enqueued_at: (Time.now.to_f * 1_000).round,
      features: feature_flags_for_payload(payload[:parent])
    )
  end

  private

  # Private: Groups the subscribed hooks for the event by parent.
  # Hookshot can handle multiple hooks per call but expects each call to contain hooks
  # for a single parent.
  #
  # Example
  #
  #   delivery_system.grouped_hooks
  #   => {
  #        "repository-1" => [hook1, hook2, hook3],
  #        "organization-42" => [hook4]
  #      }
  #
  # Returns a Hash with parent_id for keys. The values are Arrays
  # of Hooks for each unique tuple.
  def grouped_hooks
    time_grouped_hooks do
      @grouped_hooks ||= begin
        subscribed_hooks = ActiveRecord::Base.connected_to(role: :reading) { hook_event.subscribed_hooks }

        # Filter out certain classes of hooks and increment metrics.
        filtered_hooks = subscribed_hooks.select do |hook|
          # Don't select service hooks, only webhooks and cli hooks.
          # We don't care about incrementing metrics for service hooks.
          next false unless hook.webhook? || hook.cli_hook?

          # Record metrics when starting to process hooks meant for each queue (actions, chatops, internal app, hookshot).
          instrument_hook(hook)

          # Filter out any hooks on the denylist.
          !hook.on_denylist?
        end

        # Filter out Actions hooks that don't have matching workflows.
        filtered_hooks = filter_actions_hooks(filtered_hooks)

        # Group by parent ID.
        filtered_hooks.group_by(&:hookshot_parent_id)
      end
    end
  end

  # Private: Increment metrics for a single hook.
  # Increment a metric if the hook is on a denylist, or increment a different metric if it's an allowed hook.
  #
  # hook - A single hook to instrument metrics for.
  def instrument_hook(hook)
    tags = ["site:#{GitHub.site}"]
    if self.class.is_actions_delivery?(hook.hookshot_parent_id)
      tags << "queue:#{ self.class.actions_queue_for(hook.hookshot_parent_id) }"
      tags << "service:#{ACTIONS_SERVICE}"
    elsif self.class.is_chatops_integration_delivery?(hook.hookshot_parent_id)
      tags << "queue:#{ self.class.chatops_queue_for(hook.hookshot_parent_id, @hook_event) }"
      tags << "service:#{CHATOPS_SERVICE}"
    else
      tags << "queue:#{DELIVERY_QUEUE}"
      tags << "service:#{HOOKSHOT_SERVICE}"
    end
    if hook.on_denylist?
      GitHub.dogstats.increment("hooks.blocked_from_denylist.count", tags: tags)
    else
      GitHub.dogstats.increment("hooks.on_hookworker_entry.count", tags: tags)
    end
  end

  def time_grouped_hooks
    start_time = GitHub::Dogstats.monotonic_time
    yield
  ensure
    elapsed = GitHub::Dogstats.duration(start_time)
    GitHub.dogstats.distribution("hooks.grouped_hooks_duration", elapsed)
  end

  # Private: The POST payload in the format that Hookshot expects for
  # an incoming delivery trigger.
  #
  # delivery - The Hook::Delivery being delivered
  #
  # Returns a Hash.
  def hookshot_payload(delivery)
    current_installation = installation_specifics_for(delivery.parent)
    delivery_rate_limit_key, pricing_plan = hook_event.delivery_rate_limit_data
    payload = {
      parent: delivery.parent,
      guid: delivery.guid,
      event: hook_event.event_type,
      payload: delivery.payload.merge(current_installation),
      delivery_rate_limit_key: delivery_rate_limit_key,
      pricing_plan: pricing_plan
    }.tap do |hash|
      hash[:hooks] = delivery.hooks.map do |hook|
        hook_config_for(delivery, hook, current_installation)
      end
    end

    payload_size = payload.to_json(dangerously_allow_all_keys: true).bytesize
    tags = GitHub::TaggingHelper.create_hook_event_tags(hook_event.event_type, hook_event.try(:action))
    tags += ["is_large_aqueduct_payload:#{GitHub::Aqueduct.is_payload_size_large?(payload_size)}"]
    GitHub.dogstats.distribution("hooks.hookshot_payload.payload_size", payload_size, tags: tags)

    if GitHub.flipper[:webhooks_log_large_payloads].enabled? && GitHub::Aqueduct.is_payload_size_large?(payload_size)
      GitHub.logger.warn("oversized payload", {
        "gh.request_id" => GitHub.context[:request_id],
        "code.namespace" => "Hook::DeliverySystem",
        "code.function" => "hookshot_payload",
        "gh.catalog_service" => "github/webhooks",
        "gh.webhook.delivery_guid" => hook_event.guid,
        "gh.webhook.event_type" => hook_event.event_type,
        "gh.repo.id" => hook_event.target_repository&.id,
        "gh.repo.global_id" => hook_event.target_repository&.global_relay_id
      })
    end

    if payload_size > GitHub.hookshot_payload_size_limit
      delivery.hooks.each do
        GitHub.dogstats.distribution("hooks.hookshot_payload.payload_too_large", payload_size, tags: tags)
      end
      raise PayloadTooLarge, "Payload size of #{payload_size} exceeds limit: #{GitHub.hookshot_payload_size_limit}, will not be delivered to Hookshot."
    end
    payload
  end

  def hook_config_for(delivery, hook, current_installation)
    {
      id: hook.id,
      service: hook.name,
      configuration: {
        needs_public_key_signature: self.class.needs_public_key_signature?(hook),
      },
      headers: delivery.headers_for(hook),
      data: hook.config_with_tenant_scoped_url,
      callback_url: "#{GitHub.api_url}/hooks/#{delivery.guid}/#{hook.id}",
    }.tap do |hook_data|
      hook_data[:metadata] = {
        repo_id: delivery&.target_repository&.id,
        installation_id: current_installation.dig(:installation, :id),
      }
    end
  end

  def should_generate_hookshot_payloads?
    return false if Rails.env.test? && !Hook.delivers_in_test?
    return false unless hook_event.deliverable?
    return false if hook_event.model_importing?
    return false if hook_event.target_repository_disallows_hooks?
    true
  end

  # Prepares a payload for the current hook event and triggers a job
  # which will install the actions app and send the payload to the
  # actions aqueduct queue
  def install_actions_app_and_queue_event
    delivery = Hook::Delivery.new(hook_event, "integration-#{GitHub.launch_github_app&.id}", [])
    payload = hookshot_payload(delivery)
    processed_payload = payload.dup.tap do |hash|
      hash[:hook] = {}
      hash.delete(:hooks)
    end
    processed_payload = augment_payload(processed_payload)

    Actions::EnableActionsOnRepositoryJob.perform_later(
      processed_payload,
      hook_event.target_repository.id,
      { entry_point: :hook_delivery_install_actions_app_and_queue_event }
    )
  end

  def filter_actions_hooks(hooks)
    return hooks unless hook_event.target_repository

    actions_triggered_event = is_filterable_actions_triggered_event?
    return hooks if !actions_triggered_event && !hook_event.filterable_for_actions?

    time_filter_actions_hooks do
      actions_hooks, other_hooks = hooks.partition { |hook| is_actions_delivery?(hook.hookshot_parent_id) }
      return hooks unless actions_hooks.any?

      # Skip hooks triggered by Actions
      if actions_triggered_event
        instrument_actions_app_hook_filter
        return other_hooks
      end

      # Send hooks if either Actions environment has matching triggers
      has_workflows = actions_hooks.any? do |hook|
        lab = is_actions_lab_delivery?(hook.hookshot_parent_id)
        hook_event.target_repository.has_workflow_trigger_for?(hook_event.event_type, lab: lab)
      end

      return hooks if has_workflows

      instrument_actions_hook_filter
      other_hooks
    end
  end

  def time_filter_actions_hooks
    start_time = GitHub::Dogstats.monotonic_time
    yield
  ensure
    elapsed = GitHub::Dogstats.duration(start_time)
    GitHub.dogstats.distribution("actions.filter_hooks", elapsed)

    # If filtering took a significant amount of time, log the request id and repo so we can investigate
    # the number of workflows and possible impact to API response times.
    if elapsed > 200
      GitHub::logger.info("filtering took significant time", {
        "gh.request_id" => GitHub.context[:request_id],
        "code.namespace" => "Hook::DeliverySystem",
        "code.function" => "time_filter_actions_hooks",
        "gh.catalog_service" => "github/actions_experience",
        "gh.webhook.delivery_guid" => hook_event.guid,
        "gh.webhook.event_type" => hook_event.event_type,
        "gh.repo.id" => hook_event.target_repository.id,
        "gh.repo.global_id" => hook_event.target_repository.global_relay_id
      })
    end
  end

  def instrument_actions_hook_filter
    GitHub.dogstats.increment("actions.hooks.ignored", tags: ["event_type:#{hook_event.event_type}", "reason:workflow_filter"])

    GitHub::logger.info("Ignoring Actions hook - repo has no workflow triggers for event type", {
      "gh.request_id" => GitHub.context[:request_id],
      "code.namespace" => "Hook::DeliverySystem",
      "code.function" => "filter_actions_hooks",
      "gh.catalog_service" => "github/actions_experience",
      "gh.webhook.delivery_guid" => hook_event.guid,
      "gh.webhook.event_type" => hook_event.event_type,
      "gh.repo.id" => hook_event.target_repository.id,
      "gh.repo.global_id" => hook_event.target_repository.global_relay_id
    })
  end

  # Private: Publishes metadata about the delivery of each hook to hydro
  #
  # delivery - The Hook::Delivery that was delivered
  #
  # Returns an array of instrumented hooks.
  def instrument_delivery(delivery)
    return if GitHub.enterprise?
    custom_delivery = if is_actions_delivery?(delivery.parent)
      :ACTIONS
    elsif self.class.is_chatops_integration_delivery?(delivery.parent)
      :CHATOPS
    else
      nil
    end

    delivery.hooks.each do |hook|
      GlobalInstrumenter.instrument("webhook.delivery_metadata", {
        hook: hook,
        safe_hook_url: safe_hook_url(hook),
        hook_event: hook_event,
        hook_payload: delivery.hookshot_payload,
        hook_custom_delivery: custom_delivery,
        request_id: GitHub.context[:request_id]
      })
    end
  end

  # Private: Strips sensitive data from the hook url for logging to hydro
  #
  # hook - the hook we want a safe url for
  #
  # Returns the safe url
  def safe_hook_url(hook)
    url = URI.parse(hook.url)
    url.user, url.password, url.query = nil
    url.to_s
  rescue URI::InvalidURIError
    ""
  end

  def hookshot_client_for(delivery)
    @hookshot_clients ||= {}
    @hookshot_clients[delivery.parent] ||= Hookshot::Client.for_parent(delivery.parent)
  end

  def installation_specifics_for(parent, role = :reading)
    integration_id = parent.sub("integration-", "") if parent.include? "integration-"
    return {} unless integration_id

    subscribed_installation = read_subscribed_installation(role, integration_id, hook_event)
    if subscribed_installation.present?
      GitHub.dogstats.increment("hooks.subscribed_installations", tags: ["installations:present", "role:#{role}"])
      {
        installation: {
          id: subscribed_installation.id,
          node_id: subscribed_installation.global_relay_id,
        },
      }
    else
      unless role == :writing
        integration = Integration.find_by(id: integration_id)
        if integration && Flipper[:installation_specifics_for_fallback].enabled?(integration)
          return installation_specifics_for(parent, :writing)
        end
      end
      GitHub.dogstats.increment("hooks.subscribed_installations", tags: ["installations:none", "role:#{role}"])
      {}
    end
  end

  # Private: attempts to retrieve the installation associated with the hook_event
  def read_subscribed_installation(role, integration_id, hook_event)
    ActiveRecord::Base.connected_to(role: role) do
      case hook_event.event_type
      when "installation_target"
        IntegrationInstallation.with_target(hook_event.target).select(:id).find_by(integration_id: integration_id)
      else
        hook_event.subscribed_installations_for(integration_id).select(:id).first
      end
    end
  end

  def augment_payload(payload)
    self.class.augment_payload(payload)
  end

  # Private: instruments a DD timing to time requests to Hookshot and log some info before
  # and after each request.
  #
  # metric             - the metric name to send to DD
  # payload (optional) - the actual payload to be sent to hookshot as the first try
  #                      or as a redelivery
  #
  # Returns the result of the yielded block.
  def self.time_and_log_request(metric, payload = nil, tags = [])
    payload ||= {}
    log_data = payload.slice(:event, :guid, :hook_id)
    event = payload[:event]

    if event
      action = payload[:payload].try(:[], :action)
      tags += GitHub::TaggingHelper.create_hook_event_tags(event, action)
    end

    start = Time.now
    status, body = begin
      yield if block_given?
    rescue => e # rubocop:todo Lint/GenericRescue
      tags << "exception:#{e.class.name&.underscore}"
      GitHub.dogstats.increment("hooks.delivery_error.count", tags: tags)
      raise e
    end
    ending = Time.now

    tags << "status:#{status}"

    request_ms = (ending - start) * 1000
    GitHub.dogstats.distribution(metric, request_ms, tags: tags)

    [status, body]
  end
  private_class_method :time_and_log_request
end
