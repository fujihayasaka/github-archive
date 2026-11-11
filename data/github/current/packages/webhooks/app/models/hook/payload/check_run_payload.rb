# typed: true
# frozen_string_literal: true

class Hook::Payload::CheckRunPayload < Hook::Payload
  include Formatter

  def to_payload_hash
    run = api_serialize(:check_run_hash, check_run, repo: check_run.repository).tap do |opts|
      opts[:check_suite] = api_serialize(:simple_check_suite_hash, check_run.check_suite)
    end

    {}.tap do |opts|
      opts[:action]           = hook_event.action
      opts[:check_run]        = run
      if hook_event.action.to_s == "requested_action"
        hook_event.requested_action.symbolize_keys!
        opts[:requested_action] = {}
        opts[:requested_action][:identifier] = hook_event.requested_action[:identifier]
      end
    end
  end

  private

  def check_run
    hook_event.check_run
  end
end
