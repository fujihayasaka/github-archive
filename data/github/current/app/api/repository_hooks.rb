# typed: true
# frozen_string_literal: true

class Api::RepositoryHooks < Api::App
  include ReceiveSchemaWithOpenApi
  include Api::App::PackageV2ApiCheck

  # List webhooks for a repo
  get "/repositories/:repository_id/hooks", operation_id: "repos/list-webhooks" do
    control_access :list_repo_hooks,
      repo: repo = find_repo!,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    hook_scope = Hook.hooks_for_target(repo).includes(:event_types, :config_attribute_records, :installation_target)
    hooks = Hook::StatusLoader.load_statuses(hook_records: paginate_rel(hook_scope), parent: repo)
    # `hooks` is an Array, not a Relation, so set the collection size manually
    # (Usually `deliver(...)` would infer pagination info from the given collection.)
    paginator.collection_size = Hook.hooks_for_target(repo).count
    deliver :repo_hook_hash, hooks, repo: repo
  end

  # Get a single webhook
  get "/repositories/:repository_id/hooks/:hook_id", operation_id: "repos/get-webhook" do
    control_access :read_repo_hook,
    repo: repo = find_repo!,
    allow_integrations: true,
    allow_user_via_granular_actor: true

    hook = Hook::StatusLoader.load_status(find_hook(repo))
    deliver :repo_hook_hash, hook, full: true, repo: repo, last_modified: calc_last_modified_for_object(hook)
  end

  # Get a single webhook's config
  get "/repositories/:repository_id/hooks/:hook_id/config", operation_id: "repos/get-webhook-config-for-repo" do
    control_access :read_repo_hook,
      repo: repo = find_repo!,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    if hook = find_hook(repo)
      deliver_raw hook.masked_config, last_modified: calc_last_modified_for_object(hook)
    else
      deliver_error! 404
    end
  end

  # trigger a test hook call (singular, deprecated)
  #
  # DEPRECATED: Will be removed in API v4.
  post "/repositories/:repository_id/hooks/:hook_id/test", operation_id: :deprecated do
    @route_owner = "@github/ecosystem-events"
    control_access :test_repo_hook,
      repo: repo = find_repo!,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    if hook = find_hook(repo)
      Webhooks.domain.send_test_webhook(hook: hook)
      deliver_empty(status: 204)
    else
      deliver_error! 404
    end
  end

  # trigger a test hook call
  post "/repositories/:repository_id/hooks/:hook_id/tests", operation_id: "repos/test-push-webhook" do
    receive_with_schema("hook", "test")

    control_access :test_repo_hook,
      repo: repo = find_repo!,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    if hook = find_hook(repo)
      Webhooks.domain.send_test_webhook(hook: hook)
      deliver_empty(status: 204)
    else
      deliver_error! 404
    end
  end

  # Ping the hook
  post "/repositories/:repository_id/hooks/:hook_id/pings", operation_id: "repos/ping-webhook" do
    receive_with_schema("hook", "ping")

    repo = find_repo!
    @accepted_scopes << "read:repo_hook"
    control_access :test_repo_hook,
      repo: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    if hook = find_hook(repo)
      hook.ping
      deliver_empty(status: 204)
    else
      deliver_error! 404
    end
  end

  # Create a new webhook
  post "/repositories/:repository_id/hooks", operation_id: "repos/create-webhook" do
    control_access :create_repo_hook,
      repo: repo = find_repo!,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    authorize_content(repo, :create)

    data = receive_with_schema("hook", "create-legacy")
    name = data["name"] || "web"

    unless name == "web" || name == "cli"
      deliver_error! 422,
        errors: [api_error(:Hook, :name, :invalid, value: name)],
        documentation_url: @documentation_url
    end
    if name == "cli"
      # This is a placeholder URL that will be replaced by hookshot-go.
      # TODO: We have many places that expect a URL and would require a refactor
      # to start persisting webhooks without URLs.
      url = GitHub.webhook_forwarder_url.gsub("wss://", "https://").gsub("ws://", "http://")
      data["config"]["url"] = "#{url}/hook"
    end

    hook = Hook.new(installation_target: repo, name:)
    hook.track_creator(current_user)

    disallow_package_v2(Array(data["events"]))

    hook.events = Array(data["events"])
    hook.add_events("push") if hook.events.blank?

    is_new_hook = hook.new_record?
    is_active = (data["active"] != false)
    if hook.configure_with(is_active, data["config"])
      hook = hook.reload
      deliver :repo_hook_hash, hook, status: is_new_hook ? 201 : 200,
        full: true, repo: repo
    else
      deliver_error 422,
        errors: hook.errors,
        documentation_url: @documentation_url
    end
  end

  verbs :post, :patch, "/repositories/:repository_id/hooks/:hook_id", operation_id: "repos/update-webhook" do
    control_access :update_repo_hook,
      repo: repo = find_repo!,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    hook = Hook::StatusLoader.load_status(find_hook(repo))
    deliver_error! 404 unless hook

    data = receive_with_schema("hook", "update-legacy")

    attributes = attr(data, :active, :config)
    unless (active = attributes["active"]).nil?
      hook.active = active
    end
    if (config = attributes["config"]).present?
      hook.config = config
    end
    if (events = Array(data["events"])).present?
      disallow_package_v2(events)
      hook.events = events
    elsif (events = Array(data["add_events"])).present?
      disallow_package_v2(events)
      hook.add_events(events)
    elsif (events = Array(data["remove_events"])).present?
      hook.remove_events(events)
    end

    if hook.save
      deliver :repo_hook_hash, hook
    else
      deliver_error 422,
        errors: hook.errors,
        documentation_url: @documentation_url
    end
  end

  # Replace a webhook's config
  put "/repositories/:repository_id/hooks/:hook_id/config", operation_id: :deprecated do
    @route_owner = "@github/ecosystem-events"
    control_access :update_repo_hook,
      repo: repo = find_repo!,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    hook = find_hook(repo)
    deliver_error! 404 unless hook

    data = receive(Hash)
    hook.config = data

    if hook.save
      deliver_raw hook.config
    else
      deliver_error 422, errors: hook.errors
    end
  end

  # Update a service hook's config
  verbs :patch, :post, "/repositories/:repository_id/hooks/:hook_id/config", operation_id: "repos/update-webhook-config-for-repo" do
    control_access :update_repo_hook,
      repo: repo = find_repo!,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    hook = find_hook(repo)
    deliver_error! 404 unless hook

    data = receive_with_schema("hook-config", "update")
    hook.partial_config = data

    if hook.save
      deliver_raw hook.masked_config
    else
      deliver_error 422, errors: hook.errors
    end
  end

  # Delete a webhook
  delete "/repositories/:repository_id/hooks/:hook_id", operation_id: "repos/delete-webhook" do
    # Introducing strict validation of the hook.delete
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_schema("hook", "delete", skip_validation: true)

    control_access :delete_repo_hook,
      repo: repo = find_repo!,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    hook = find_hook(repo)
    if hook && hook.destroy
      deliver_empty(status: 204)
    else
      deliver_error 404
    end
  end

  # Fetch the deliveries of a specific hook
  get "/repositories/:repository_id/hooks/:hook_id/deliveries", operation_id: "repos/list-webhook-deliveries" do

    control_access :list_repo_hooks,
      repo: repo = find_repo!,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    hook = find_hook(repo)
    deliver_error!(404) unless hook

    ensure_data_satisfies_schema!(request.GET, "hook", "deliveries")

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

  # Get a single delivery of a given webhook
  get "/repositories/:repository_id/hooks/:hook_id/deliveries/:delivery_id", operation_id: "repos/get-webhook-delivery" do
    control_access :read_repo_hook,
      repo: repo = find_repo!,
      allow_integrations: true,
      allow_user_via_granular_actor: true
    ensure_data_satisfies_schema!(request.GET, "hook", "delivery")

    hook = find_hook(repo)

    deliver_error!(404) unless hook

    status, body = HookDeliveriesClient.new(hook).delivery_for_hook(params[:delivery_id], hook.id, { include_payload: true })

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
  post "/repositories/:repository_id/hooks/:hook_id/deliveries/:delivery_id/attempts", operation_id: "repos/redeliver-webhook-delivery" do

    repo = find_repo!
    control_access :update_repo_hook,
      repo: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    receive_with_schema("hook", "redelivery")

    hook = find_hook(repo)
    deliver_error!(404) unless hook

    hook_client = HookDeliveriesClient.new(hook)

    status, body = hook_client.delivery_for_hook(params[:delivery_id], hook.id, {})
    GitHub.dogstats.increment("webhooks_redelivery_attempted", tags: ["method: api", "type: repo"])
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

  def per_page(limit)
    return DEFAULT_PER_PAGE unless limit
    [limit.to_i, MAX_PER_PAGE].min
  end

  # TODO: Make Egress properly report accepted scopes and remove this overload.
  def find_repo!
    repo = super

    @accepted_scopes = %w(admin:repo_hook repo)
    @accepted_scopes << "read:repo_hook" if request.get? || request.head?
    @accepted_scopes << "write:repo_hook" unless request.delete?
    @accepted_scopes << "public_repo" if repo && repo.public?

    repo
  end

  def find_hook(repo)
    Hook.hooks_for_target(repo).find_by(id: int_id_param!(key: :hook_id))
  end

  def authorize_content(authorizable, operation = :create)
    authorization = ContentAuthorizer.authorize(current_user, :hook, operation, repo: authorizable)
    deliver_content_authorization_denied!(authorization) if authorization.failed?
  end
end
