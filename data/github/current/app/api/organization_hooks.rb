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

  post "/organizations/:organization_id/hooks/:hook_id/pings", operation_id: "orgs/ping-webhook", read_from_replicas: true do
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

  post "/organizations/:organization_id/hooks", operation_id: "orgs/create-webhook", read_from_replicas: true do
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

    with_write(clusters: [ApplicationRecord::Mysql1]) do
      if hook.save
        deliver :org_hook_hash, hook, status: 201,
          full: true
      else
        deliver_error 422,
          errors: hook.errors,
          documentation_url: @documentation_url
      end
    end
  end

  patch "/organizations/:organization_id/hooks/:hook_id", operation_id: "orgs/update-webhook", read_from_replicas: true do
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

    with_write(clusters: [ApplicationRecord::Mysql1]) do
      if hook.update attributes
        deliver :org_hook_hash, hook
      else
        deliver_error 422,
          errors: hook.errors,
          documentation_url: @documentation_url
      end
    end
  end

  verbs :patch, :post, "/organizations/:organization_id/hooks/:hook_id/config", operation_id: "orgs/update-webhook-config-for-org", read_from_replicas: true do
    org = find_org!
    control_access :update_org_hook,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    hook = find_hook!(param_name: :hook_id)
    data = receive_with_schema("hook-config", "update")
    hook.partial_config = data

    with_write(clusters: [ApplicationRecord::Mysql1]) do
      if hook.save
        deliver_raw hook.masked_config
      else
        deliver_error errors: hook.errors
      end
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

  delete "/organizations/:organization_id/hooks/:hook_id", operation_id: "orgs/delete-webhook", read_from_replicas: true do
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
    with_write(clusters: [ApplicationRecord::Mysql1]) do
      if hook.destroy
        deliver_empty(status: 204)
      else
        deliver_error 404
      end
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
                               :events, :is_redelivery, :guid, :repo_id)

    # filtering is only allowed if the feature flag is on
    unless FeatureFlag.vexi.enabled?(:hook_deliveries_api_filtering, hook.installation_target, default: false)
      disallowed_filters = safe_params.except(:cursor, :per_page, :status)
      if disallowed_filters.any?
        error_messages = disallowed_filters.keys.map { |k| "\"#{k}\" is not a permitted key." }.join("\n")
        deliver_error! 422, message: "Invalid request.\n\n#{error_messages}"
      end
    end

    request_args = safe_params.except(:per_page, :is_redelivery)

    # Rename parameters
    if safe_params.include?(:per_page)
      request_args[:limit] = per_page(safe_params[:per_page])
    end

    if safe_params.include?(:is_redelivery)
      request_args[:redelivery] = safe_params[:is_redelivery]
    end

    status, body = HookDeliveriesClient.new(hook).deliveries_for_hook(hook.id, request_args)

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

    delivery_id = int_id_param!(key: :delivery_id, halt: true).to_s
    status, body = HookDeliveriesClient.new(hook).delivery_for_hook(delivery_id, hook.id, { include_payload: true })

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
  post "/organizations/:organization_id/hooks/:hook_id/deliveries/:delivery_id/attempts", operation_id: "orgs/redeliver-webhook-delivery", read_from_replicas: true do
    org = find_org!
    control_access :update_org_hook,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    receive_with_schema("organization-hook", "redelivery")

    hook = find_hook!(param_name: :hook_id)
    deliver_error!(404) unless hook

    hook_client = HookDeliveriesClient.new(hook)

    delivery_id = int_id_param!(key: :delivery_id, halt: true).to_s
    status, body = hook_client.delivery_for_hook(delivery_id, hook.id, {})
    GitHub.dogstats.increment("webhooks_redelivery_attempted", tags: ["method: api", "type: org"])
    case status
    when 200
      hook_client.redeliver(delivery_id: delivery_id, delivery_guid: body["guid"], hook: hook)
      deliver_empty status: 202
    when 404
      deliver_error!(404)
    when 400, 422
      deliver_error! status, message: body["message"]
    else
      deliver_error! 500, message: "Something went wrong."
    end
  end

  private

  def rate_limit_configuration
    return nil if FeatureFlag.vexi.enabled?(:gateway_webhook_deliveries_rate_limiter_disabled, current_user, default: false)

    Api::RateLimitConfiguration.for(
      Api::RateLimitConfiguration::WEBHOOK_DELIVERIES_FAMILY,
      self,
    )
  end

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
