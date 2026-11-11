# typed: true
# frozen_string_literal: true

class Hook::Payload::CheckSuitePayload < Hook::Payload
  include Formatter

  def to_payload_hash
    {}.tap do |opts|
      opts[:action]      = hook_event.action
      check_suite_hash   = api_serialize(:check_suite_hash, check_suite)
      opts[:check_suite] = check_suite_hash.tap do |hs|
        hs.delete(:repository)
      end
      opts[:actions_meta] = hook_event.actions_meta
    end
  end

  private

  def check_suite
    hook_event.check_suite
  end
end
