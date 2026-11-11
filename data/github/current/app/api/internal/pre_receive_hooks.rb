# typed: true
# frozen_string_literal: true

class Api::Internal::PreReceiveHooks < Api::Internal

  before do
    deliver_error!(404) unless GitHub.enterprise_only_api_enabled?
  end

  # Internal: After a failed execution of a custom pre-receive hook,
  # this endpoint is notified about the error.
  post "/internal/pre-receive-hooks/:pre_receive_hook_id/errors", operation_id: :internal do
    @route_owner = "@github/meao"
    hook = find_pre_receive_hook!(param_name: :pre_receive_hook_id)

    data = receive_with_schema("pre-receive-hook-error", "create")
    decode_push_data!(data)

    enqueue_error_job(hook, data)

    deliver_empty status: 202
  end

  def externally_accessible?
    false
  end

  def require_request_hmac?
    true
  end

  def authenticated_for_private_mode?
    true
  end

  private

  def enqueue_error_job(hook, data)
    mapped_ref_updates = data["ref_updates"].each_with_object(String.new) do |ref_update, refs|
      refs << "#{ref_update["before_oid"]} #{ref_update["after_oid"]} #{ref_update["refname"]}\n"
    end

    arguments = [
      data["repo_path"],
      data["pusher"],
      mapped_ref_updates,
      data["protocol"],
      hook.environment_id,
      hook.environment&.checksum,
      hook.id,
      data["hook_warning"],
      data["hook_error"],
      data["real_ip"],
    ]

    RepositoryPreReceiveJob.perform_later(*arguments)
  end
end
