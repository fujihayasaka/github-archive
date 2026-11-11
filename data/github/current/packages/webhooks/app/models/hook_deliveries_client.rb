# typed: true
# frozen_string_literal: true

class HookDeliveriesClient
  extend T::Helpers
  attr_reader :options

  sig { params(hook: Hook, ui: T::Boolean).void }
  def initialize(hook, ui: true)
    @parent = hook.hookshot_parent_id
    @primary_client = ui ? Hookshot::Client.ui_client_for_parent(@parent) : Hookshot::Client.for_parent(@parent)
  end

  def delivery_for_hook(delivery_id, hook_id, options)
    @primary_client.delivery_for_hook(delivery_id, hook_id, options)
  end

  def deliveries_for_hook(hook_id, params)
    @primary_client.deliveries_for_hook(hook_id, params)
  end

  def redeliver(delivery_id: nil, delivery_guid: nil, hook:)
    if !delivery_id
      raise ArgumentError.new("redeliveries require a delivery_id")
    end

    Hook::DeliverySystem.redeliver(delivery_guid, hook, delivery_id.to_i)
  end

  def statuses_for_hooks(hook_ids)
    @primary_client.statuses_for_hooks(hook_ids)
  end
end
