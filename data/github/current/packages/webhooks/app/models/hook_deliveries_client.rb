# typed: true
# frozen_string_literal: true

class HookDeliveriesClient
  extend T::Helpers
  attr_reader :options

  class WebhookDeliveriesTrafficDisabled < StandardError; end

  sig { params(hook: Hook, ui: T::Boolean).void }
  def initialize(hook, ui: true)
    parent = hook.hookshot_parent_id
    @webhook_deliveries_traffic_enabled = GitHub.webhook_deliveries_url.present? && GitHub.webhook_deliveries_token.present? && Events::ParentAsActor.new(parent).feature_enabled?(:webhook_deliveries_traffic)
    @events_v2_enabled = Events::ParentAsActor.new(parent).feature_enabled?(:events_v2_owner_enabled)
    # For repository hooks, we want to also check if the organization is enabled for Events V2 deliveries.
    if !@events_v2_enabled && hook.installation_target.is_a?(Repository) && hook.installation_target.organization_id
      @events_v2_enabled = T.must(Events::ParentAsActor.org_actor(hook.installation_target.organization_id)).feature_enabled?(:events_v2_owner_enabled)
    end

    # We always initialize the v1 and v2 clients for redelivery purposes.
    # V2 redeliveries can only be redelivered by webhook-deliveries.
    # Legacy redeliveries can only be redelivered by hookshot-go.
    # If webhook-deliveries traffic is totally disabled, then we won't be able
    # to redeliver Events V2 events, so this should only be done in an emergency.
    if @webhook_deliveries_traffic_enabled
      @v2_client = WebhookDeliveriesClient.new(parent)
    end
    @v1_client = ui ? Hookshot::Client.ui_client_for_parent(parent) : Hookshot::Client.for_parent(parent)

    # For other API calls we can use primary and fallback clients to switch between
    # webhook-deliveries and hookshot-go depending on the status of the feature flag.
    # This is used to gracefully switch between the two services during rollout
    # of Events V2.
    if @events_v2_enabled && @webhook_deliveries_traffic_enabled
      @primary_client = @v2_client
      @fallback_client = @v1_client
    elsif @webhook_deliveries_traffic_enabled
      @primary_client = @v1_client
      @fallback_client = @v2_client
    else
      @primary_client = @v1_client
    end
  end

  def delivery_for_hook(delivery_id, hook_id, options)
    status, body = @primary_client.delivery_for_hook(delivery_id, hook_id, options)
    if options[:include_payload] && ((status == 500 && body["message"] == "BlobNotFound") || (status == 404)) && @fallback_client.present?
      status, body = @fallback_client.delivery_for_hook(delivery_id, hook_id, options)
    end
    [status, body]
  end

  def deliveries_for_hook(hook_id, params)
    @primary_client.deliveries_for_hook(hook_id, params)
  end

  def redeliver(delivery_id: nil, delivery_guid: nil, hook:, v2: false)
    # Redeliveries in Events V2 use the delivery_id numeric ID (the same ID the
    # API uses for redeliveries) vs the Event GUID. Legacy redeliveries use the
    # event GUID.
    if v2 && !delivery_id
      raise ArgumentError.new("V2 redeliveries require a delivery_id")
    elsif !v2 && !delivery_guid
      raise ArgumentError.new("V1 redeliveries require a delivery_guid")
    end

    return redeliver_v2(delivery_id: delivery_id, hook: hook) if v2
    redeliver_v1(delivery_guid: delivery_guid, hook: hook)
  end

  def statuses_for_hooks(hook_ids)
    @primary_client.statuses_for_hooks(hook_ids)
  end

  private

  def redeliver_v1(delivery_guid:, hook:)
    Hook::DeliverySystem.redeliver(delivery_guid, hook)
  end

  def redeliver_v2(delivery_id:, hook:)
    # We would only disable webhook-deliveries traffic in an emergency, in which case
    # it is impossible to redeliver the delivery so the user should see an error.
    raise WebhookDeliveriesTrafficDisabled.new("Cannot redeliver V2 delivery. webhook-deliveries traffic is disabled.") unless @webhook_deliveries_traffic_enabled

    webhook_subscription = {
      webhook: {
        id: hook.id,
        service: hook.name,
        needs_public_key_signature: Hook::DeliverySystem.needs_public_key_signature?(hook),
        configuration: {
          url: hook.url,
          content_type: hook.content_type,
          insecure_ssl: hook.insecure_ssl
        }
      },
      parent: hook.hookshot_parent_id
    }
    status, response = @v2_client.redeliver(delivery_id: delivery_id.to_i, webhook_subscription: webhook_subscription)
    if status != 200
      raise Hookshot::BadResponseError.new(status, response)
    end
    true
  end
end
