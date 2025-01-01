# typed: true
# frozen_string_literal: true

class Hook::Delivery
  include GitHub::Memoizer

  attr_reader :hook_event, :parent, :hooks, :muted_hooks
  attr_accessor :hookshot_payload

  def initialize(hook_event, parent, hooks)
    @hook_event = hook_event
    @parent = parent
    @hooks, @muted_hooks = hooks.partition { |h| delivery_allowed_for_hook?(h) }
  end

  def payload
    hook_event.to_payload_hash
  end

  memoize def payload_size
    payload.to_json(dangerously_allow_all_keys: true).bytesize
  end

  def headers_for(hook)
    hook_event.headers_for(hook)
  end

  def guid
    hook_event.guid
  end

  def target_repository
    hook_event.target_repository
  end

  private

  def delivery_allowed_for_hook?(hook)
    OauthApplicationPolicy::Hook.new(hook, hook_event).satisfied?
  end
end
