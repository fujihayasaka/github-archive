# typed: true
# frozen_string_literal: true

class Api::Admin::Webhooks < Api::Admin

  get "/admin/hooks", operation_id: "enterprise-admin/list-global-webhooks" do # rubocop:todo GitHub/ControlAccess
    hook_scope = GitHub.global_business.hooks.includes(:event_types, :config_attribute_records, :installation_target)
    hooks = paginate_rel(hook_scope)
    deliver :global_hook_hash, hooks
  end

  # rubocop:todo GitHub/ControlAccess
  get "/admin/hooks/:hook_id", operation_id: "enterprise-admin/get-global-webhook" do
    hook = find_hook!
    deliver :global_hook_hash, hook, full: true, last_modified: calc_last_modified(hook)
  end
  # rubocop:enable GitHub/ControlAccess

  # rubocop:todo GitHub/ControlAccess
  post "/admin/hooks/:hook_id/pings", operation_id: "enterprise-admin/ping-global-webhook" do
    hook = find_hook!
    hook.ping
    deliver_empty(status: 204)
  end
  # rubocop:enable GitHub/ControlAccess

  post "/admin/hooks", operation_id: "enterprise-admin/create-global-webhook" do # rubocop:todo GitHub/ControlAccess
    data = receive(Hash)
    hook = Hook.new(
      name: data["name"],
      events: Array(data.fetch("events", "*")),
      active: true,
      config: data["config"],
      installation_target: GitHub.global_business,
    )
    hook.track_creator(current_user)
    if hook.save
      deliver :global_hook_hash, hook, status: 201, full: true
    else
      deliver_error 422, errors: hook.errors, documentation_url: @documentation_url
    end
  end

  # rubocop:todo GitHub/ControlAccess
  verbs :post, :patch, "/admin/hooks/:hook_id", operation_id: "enterprise-admin/update-global-webhook" do
    hook = find_hook!
    data = receive(Hash)
    attributes = attr(data, :active, :config)
    if (events = Array(data["events"])).present?
      attributes[:events] = events
    end
    if hook.update attributes
      deliver :global_hook_hash, hook
    else
      deliver_error 422,
        errors: hook.errors,
        documentation_url: @documentation_url
    end
  end
  # rubocop:enable GitHub/ControlAccess

  # rubocop:todo GitHub/ControlAccess
  delete "/admin/hooks/:hook_id", operation_id: "enterprise-admin/delete-global-webhook" do
    hook = find_hook!
    deliver_error! 422, errors: hook.errors unless hook.destroy
    deliver_empty status: 204
  end
  # rubocop:enable GitHub/ControlAccess

  private

  def find_hook!
    GitHub.global_business.hooks.find_by_id(int_id_param!(key: :hook_id)) || deliver_error!(404)
  end

end
