# typed: true
# frozen_string_literal: true

class Api::OrganizationHooks < Api::App
  include ReceiveSchemaWithOpenApi
  include Api::App::PackageV2ApiCheck

  get "/organizations/:organization_id/hooks", operation_id: "orgs/list-webhooks" do
    org = find_org!
    control_access :list_org_hooks,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    hooks = paginate_rel(filtered_hooks.includes(:event_types, :config_attribute_records, :installation_target))
    deliver :org_hook_hash, hooks
  end

  get "/organizations/:organization_id/hooks/:hook_id", operation_id: "orgs/get-webhook" do
    org = find_org!
    control_access :read_org_hook,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    hook = find_hook!(param_name: :hook_id)
    deliver :org_hook_hash, hook, full: true, last_modified: calc_last_modified_for_object(hook)
  end

  post "/organizations/:organization_id/hooks/:hook_id/pings", operation_id: "orgs/ping-webhook" do
    receive_with_schema("organization-hook", "ping")

    org = find_org!
    control_access :test_org_hook,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    hook = find_hook!(param_name: :hook_id)
    hook.ping
    deliver_empty(status: 204)
  end

  post "/organizations/:organization_id/hooks", operation_id: "orgs/create-webhook" do
    org = find_org!
    control_access :create_org_hook,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    # Introducing strict validation of the organization-hook.create
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    data = receive_with_schema("organization-hook", "create", skip_validation: true)
    name = data["name"]

    if name == "cli"
      # This is a placeholder URL that will be replaced by hookshot-go.
      # TODO: We have many places that expect a URL and would require a refactor
      # to start persisting webhooks without URLs.
      url = GitHub.webhook_forwarder_url.gsub("wss://", "https://").gsub("ws://", "http://")
      data["config"]["url"] = "#{url}/hook"
    end

    hook = org.hooks.build(name: name)

    hook.track_creator(current_user)
    disallow_package_v2(Array(data["events"]))

    hook.events = Array(data["events"])
    hook.add_events("push") if hook.events.blank?
    hook.active = (data["active"] != false)
    hook.config = data["config"]

    if hook.save
      deliver :org_hook_hash, hook, status: 201,
        full: true
    else
      deliver_error 422,
        errors: hook.errors,
        documentation_url: @documentation_url
    end
  end

  patch "/organizations/:organization_id/hooks/:hook_id", operation_id: "orgs/update-webhook" do
    org = find_org!
    control_access :update_org_hook,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    hook = find_hook!(param_name: :hook_id)

    # Introducing strict validation of the organization-hook.update
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    data = receive_with_schema("organization-hook", "update", skip_validation: true)

    attributes = attr(data, :active, :config)
    if (events = Array(data["events"])).present?
      disallow_package_v2(events)
      attributes[:events] = events
    end

    if hook.update attributes
      deliver :org_hook_hash, hook
    else
      deliver_error 422,
        errors: hook.errors,
        documentation_url: @documentation_url
    end
  end

  verbs :patch, :post, "/organizations/:organization_id/hooks/:hook_id/config", operation_id: "orgs/update-webhook-config-for-org" do
    org = find_org!
    control_access :update_org_hook,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    hook = find_hook!(param_name: :hook_id)
    data = receive_with_schema("hook-config", "update")
    hook.partial_config = data

    if hook.save
      deliver_raw hook.masked_config
    else
      deliver_error errors: hook.errors
    end
  end

  get "/organizations/:organization_id/hooks/:hook_id/config", operation_id: "orgs/get-webhook-config-for-org" do
    org = find_org!
    control_access :read_org_hook,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    hook = find_hook!(param_name: :hook_id)

    deliver_raw hook.masked_config, last_modified: calc_last_modified_for_object(hook)
  end

  delete "/organizations/:organization_id/hooks/:hook_id", operation_id: "orgs/delete-webhook" do
    # Introducing strict validation of the organization-hook.delete
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_schema("organization-hook", "delete", skip_validation: true)

    org = find_org!
    control_access :delete_org_hook,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    hook = find_hook!(param_name: :hook_id)
    if hook.destroy
      deliver_empty(status: 204)
    else
      deliver_error 404
    end
  end

  # Fetch the deliveries of a specific hook
  get "/organizations/:organization_id/hooks/:hook_id/deliveries", operation_id: "orgs/list-webhook-deliveries" do
    org = find_org!
    control_access :list_org_hooks,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    hook = find_hook!(param_name: :hook_id)

    ensure_data_satisfies_schema!(request.GET, "organization-hook", "deliveries")

    safe_params = params.slice(:cursor, :per_page, :since, :until, :status, :status_code,
                               :events, :redelivery, :guid, :repo_id)

    # filtering is only allowed if the feature flag is on
    unless GitHub.flipper[:hook_deliveries_api_filtering].enabled?(hook.installation_target)
      disallowed_filters = safe_params.except("cursor").except("per_page")
      if disallowed_filters.any?
        error_messages = disallowed_filters.keys.map { |k| "\"#{k}\" is not a permitted key." }.join("\n")
        deliver_error! 422, message: "Invalid request.\n\n#{error_messages}"
      end
    end

    request_args = safe_params.except("per_page").merge(limit: per_page(safe_params["per_page"]))
    status, body = HookDeliveriesClient.new(hook.hookshot_parent_id).deliveries_for_hook(hook.id, request_args)

    case status
    when 200
      build_cursor_based_links(body["page_info"], per_page(safe_params["per_page"]))
      deliver_raw body["deliveries"]
    when 400, 422
      deliver_error! status, message: body["message"]
    else
      deliver_error! 500, message: "Something went wrong."
    end
  end

  # Fetch single delivery of a specific hook
  get "/organizations/:organization_id/hooks/:hook_id/deliveries/:delivery_id", operation_id: "orgs/get-webhook-delivery" do
    ensure_data_satisfies_schema!(request.GET, "organization-hook", "delivery")

    org = find_org!
    control_access :read_org_hook,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    hook = find_hook!(param_name: :hook_id)

    status, body = HookDeliveriesClient.new(hook.hookshot_parent_id).delivery_for_hook(params[:delivery_id], hook.id, { include_payload: true })

    case status
    when 200
      body["request"].delete("include_payload")
      body["response"].delete("include_payload")

      deliver_raw body
    when 404
      deliver_error!(404)
    when 400, 422
      deliver_error! status, message: body["message"]
    else
      deliver_error! 500, message: "Something went wrong."
    end
  end

  # Trigger a new delivery attempt
  post "/organizations/:organization_id/hooks/:hook_id/deliveries/:delivery_id/attempts", operation_id: "orgs/redeliver-webhook-delivery" do
    org = find_org!
    control_access :update_org_hook,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    receive_with_schema("organization-hook", "redelivery")

    hook = find_hook!(param_name: :hook_id)
    deliver_error!(404) unless hook

    hook_client = HookDeliveriesClient.new(hook.hookshot_parent_id)

    status, body = hook_client.delivery_for_hook(params[:delivery_id], hook.id, {})
    GitHub.dogstats.increment("webhooks_redelivery_attempted", tags: ["method: api", "type: org"])
    case status
    when 200
      hook_client.redeliver(delivery_id: params[:delivery_id], delivery_guid: body["guid"], hook: hook, v2: body["v2"])
      deliver_empty status: 202
    when 404
      deliver_error!(404)
    when 400, 422
      deliver_error! status, message: body["message"]
    else
      deliver_error! 500, message: "Something went wrong."
    end
  rescue HookDeliveriesClient::WebhookDeliveriesTrafficDisabled
    # This would only occur in emergencies if we've decided to completely turn off the webhook-deliveries API.
    # In this case user's are being impacted as they are unable to redeliver webhooks emitted from Events V2.
    deliver_error! 503, message: "Unable to redeliver at this time."
  end

  private

  def filtered_hooks
    find_org!.hooks.editable_by(current_user)
  end

  def find_hook!(param_name: :id)
    filtered_hooks.find_by_id(int_id_param!(key: param_name)) || deliver_error!(404)
  end

  def per_page(limit)
    return DEFAULT_PER_PAGE unless limit
    [limit.to_i, MAX_PER_PAGE].min
  end
end
