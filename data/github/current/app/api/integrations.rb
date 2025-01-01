# typed: true
# frozen_string_literal: true

# Provides endpoints for requests that are authenticated as the integration
# (i.e., requests using an assertion token signed with the integration's private
# key). For example, to obtain an access token for an installation, the request
# must be authenticated using an assertion token signed with the integration's
# private key.
class Api::Integrations < Api::App
  include ReceiveSchemaWithOpenApi

  INSTALLATION_SUSPENDED_MSG = "This installation has been suspended"
  INVALID_PERMISSIONS_FORMAT_MSG = "Invalid permissions format"
  VALID_PERMISSIONS_ACTIONS = %w[read write admin]
  INVALID_PERMISSIONS_ACTIONS_MSG = "There is at least one permission action that is not supported. It should be one of: \"read\", \"write\" or \"admin\"."
  INVALID_REPOSITORY_NAME_MSG = "There is at least one repository with an invalid name"

  CODEPATH_CREATE_ACCESS_TOKEN         = "api/create-installation-access-token".freeze
  CODEPATH_CREATE_SCOPED_TOKEN         = "api/create-scoped-installation-access-token".freeze
  CODEPATH_CREATE_PERMISSIONLESS_TOKEN = "api/create-permissionless-installation-access-token".freeze
  CODEPATH_CREATE_GLOBAL_TOKEN         = "api/create-global-installation-access-token".freeze

  # Internal: Overrides default auth scheme to only support Integration Bearer
  # Assertions.
  def attempt_login
    attempt_login_from_integration
  end

  # Internal: Overrides default private mode authentication check so that
  # integrations can make authenticated requests
  def authenticated_for_private_mode?
    attempt_login_from_integration && current_integration.present?
  end

  before do
    GitHub.context.push(auth: "jwt")
    Audit.context.push(auth: "jwt")
    ::Failbot.push("gh.integration.id" => current_integration.id) if current_integration

    log_data[:auth] = "jwt"
  end

  # Temporarily disable rate limiting for now.
  #
  # TODO: Implement proper rate limiting for these endpoints. Please see
  # https://github.com/github/platform/issues/560 for more context.
  rate_limit_as nil

  get "/app", operation_id: "apps/get-authenticated" do
    control_access :read_integration, resource: current_integration, allow_integrations: false, allow_user_via_granular_actor: false

    # We pass current_integration here as an extra option so that from the serializer
    # we can expose sensitive fields like installations_count when authenticated as the app
    deliver :integration_hash, current_integration, current_integration: current_integration
  end

  get "/app/installations", operation_id: "apps/list-installations" do
    control_access :read_integration_installations, resource: current_integration, allow_integrations: false, allow_user_via_granular_actor: false

    scope = params[:outdated].present? ? current_integration.outdated_installations : current_integration.installations
    scope = filter(scope.most_recent)

    paginated_installations = paginate_rel(scope).load

    GitHub::PrefillAssociations.prefill_associations(
      paginated_installations,
      [:target, :event_records, :user_suspended_by, :version, :integration],
      available_records: [current_integration]
    )

    deliver :installation_hash, paginated_installations
  end

  get "/app/installation-requests", operation_id: "apps/list-installation-requests-for-authenticated-app" do
    @route_owner = "@github/ecosystem-apps"
    @documentation_url = "/v3/apps/#find-installation-requests"

    control_access :read_integration_installation_requests,
      resource: current_integration,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      disable_conditional_access_policies: !GitHub.flipper[:api_integrations_endpoint_uses_cap].enabled?(current_integration) # rubocop:todo GitHub/DoNotSkipCapAccessAllowed

    scope = current_integration.pending_installation_requests.includes([:requester, :target])
    scope = filter(scope.most_recent)

    pending_requests = paginate_rel(scope)

    deliver :integration_installation_request_hash, pending_requests
  end

  get "/integration/installations", operation_id: :deprecated do
    @route_owner = "@github/ecosystem-apps"

    control_access :read_integration_installations, resource: current_integration, allow_integrations: false, allow_user_via_granular_actor: false

    deliver_redirect! api_url("/app/installations"), status: permanent_redirect_status_code
  end

  get "/app/installations/:installation_id", operation_id: "apps/get-installation", resolve_tenant_context: :rtc_for_installation do
    installation = find_installation!
    control_access :read_integration_installations, resource: installation, allow_integrations: false, allow_user_via_granular_actor: false

    GitHub::PrefillAssociations.prefill_associations(installation, :integration, available_records: [current_integration])

    deliver :installation_hash, installation
  end

  delete "/app/installations/:installation_id", operation_id: "apps/delete-installation", resolve_tenant_context: :rtc_for_destroyable_installation do
    receive_with_schema("installation", "delete")

    installation = find_destroyable_installation!
    control_access :delete_integration_installations, resource: installation, allow_integrations: false, allow_user_via_granular_actor: false

    installation.uninstall(actor: current_integration.owner)

    response_code = changeset_active?(:change_delete_installation_success_status) ? 202 : 204
    deliver_empty(status: response_code)
  end

  put "/app/installations/:installation_id/suspended", operation_id: "apps/suspend-installation" do
    receive_with_schema("installation", "suspend")

    installation = find_installation!
    control_access :modify_integration_installation_suspension, resource: installation, allow_integrations: false, allow_user_via_granular_actor: false

    installation.suspend!

    deliver_empty(status: 204)
  end

  delete "/app/installations/:installation_id/suspended", operation_id: "apps/unsuspend-installation" do
    receive_with_schema("installation", "unsuspend")

    installation = find_installation!
    control_access :modify_integration_installation_suspension, resource: installation, allow_integrations: false, allow_user_via_granular_actor: false

    installation.unsuspend!

    deliver_empty(status: 204)
  end

  get "/integration/installations/:installation_id", operation_id: :deprecated do
    @route_owner = "@github/ecosystem-apps"

    # rubocop:todo GitHub/DoNotSkipCapAccessAllowed
    control_access :apps_audited, allow_integrations: false, allow_user_via_granular_actor: false, disable_conditional_access_policies: true
    # rubocop:enable GitHub/DoNotSkipCapAccessAllowed
    deliver_redirect! api_url("/app/installations/#{params[:installation_id]}"), status: permanent_redirect_status_code
  end

  post "/app/installations/:installation_id/access_tokens", operation_id: "apps/create-installation-access-token", resolve_tenant_context: :rtc_for_installation do # rubocop:disable GitHub/DuplicateRoutesAreDefinedTogether
    @documentation_url = "/rest/reference/apps#create-an-installation-access-token-for-an-app"

    enforce_internal_access!

    # Introducing strict validation of the installation-token.create
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    data = receive_with_schema("installation-token", "create", skip_validation: true)
    attrs = [:permissions, :repositories, :repository_ids]
    data  = attr(data, *attrs)
    validate_access_token_request_payload!(data)
    validate_repository_names!(data[:repositories]) if GitHub.flipper[:validate_repo_name_on_access_token_creation].enabled?

    installation = ActiveRecord::Base.connected_to(role: :reading) { find_installation! }
    control_access :create_integration_installation_token, resource: installation, allow_integrations: false, allow_user_via_granular_actor: false

    GitHub.tracer.in_span("Api::Integrations::post_app_installation_access_tokens", kind: :internal) do |span|
      ActiveRecord::Base.connected_to(role: :reading) do
        deliver_error!(403, message: INSTALLATION_SUSPENDED_MSG) if installation.suspended?
        span.set_attribute("gh.integration.id", current_integration.id)
        repository_ids = fetch_repository_ids(data, installation.target)

        # ScopedIntegrationInstallation can be created using the repositories,
        # permissions or both parameters
        if should_generate_scoped_token?(repository_ids, data, installation)
          entry_point = Permissions::Service::EntryPoint.build(
            :rest_api_integrations_create_installation_access_token,
            target: installation.target,
            parent_installation: installation,
            actor_owner: current_integration,
            scope_type: entry_point_scope_type(repository_ids, installation, data),
          )

          result = generate_scoped_token(installation, repository_ids, data[:permissions], data, entry_point: entry_point)
          deliver_error!(422, message: result.error) if result.failed?
          installation = result.installation
        end

        record, token = AuthenticationToken.create_for(installation, code_path: CODEPATH_CREATE_ACCESS_TOKEN)
        options = { status: 201, token: token }

        serialization_tags = ["token_type:#{record.authenticatable.class.name.underscore}"]

        if record.authenticatable.is_a?(ScopedIntegrationInstallation)
          serialization_tags << "requested_repository_selection:#{requested_repository_selection(repository_ids, data)}"
        end

        if should_calculate_valid_after?(current_integration, installation)
          serialization_tags << "valid_after:true"
          options[:valid_after] = valid_after_for(installation, result: result)
        else
          serialization_tags << "valid_after:false"
        end

        if respond_with_lightweight_authentication_token?
          span.add_attributes("gh.installation.lightweight_payload" => true, "gh.integration.id" => current_integration.id)
          serialization_tags << "response_type:lightweight"
          options[:instrumentation_tags] = serialization_tags

          return deliver(:lightweight_authentication_token_hash, record, options)
        end

        if single_file_permission?(installation)
          options[:single_file] = installation.single_file_name
          options[:has_multiple_single_files] = installation.multiple_single_files?
          options[:single_file_paths] = installation.single_file_paths
        end

        if record.authenticatable.is_a?(ScopedIntegrationInstallation)
          with_master_or_replica(permissions_for(installation)) do
            options[:permissions] = permissions_for(installation)
            options[:repositories] = installation.repositories if scoped_token_repository_param?(data)
          end

          if options[:repositories].present?
            GitHub.tracer.in_span("prefill_associations_for_repositories", kind: :internal) do |_|
              Repository.prefill_associations(options[:repositories])
            end
          end
        else
          options[:permissions] = permissions_for(installation)
        end

        options[:repository_selection] = repository_selection(installation)

        serialization_tags += ["response_type:full", "installation_repository_selection:#{options[:repository_selection]}"]
        options[:instrumentation_tags] = serialization_tags

        deliver :authentication_token_hash, record, options
      end
    end
  end

  post "/app/installations/:installation_id/access_tokens/permissionless", operation_id: :internal do
    @route_owner = "@github/ecosystem-apps"
    enforce_internal_access!

    installation = ActiveRecord::Base.connected_to(role: :reading) { find_installation! }
    control_access :create_integration_installation_token,
      resource: installation,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    result = ScopedIntegrationInstallation::Creator.perform_with_cache(installation, permissions: :none, entry_point: :rest_api_integrations_create_permissionless_installation_access_token_internal)

    if result.failed?
      deliver_error!(422, message: result.error)
    end

    record, token = AuthenticationToken.create_for(result.installation, code_path: CODEPATH_CREATE_PERMISSIONLESS_TOKEN)
    deliver :authentication_token_hash, record, { status: 201, token: token, permissions: {} }
  end

  patch "/app/installation/access_tokens", operation_id: :internal do
    @route_owner = "@github/ecosystem-apps"
    unless ::Apps::Privileged.capable?(:extend_access_token_expiry, app: current_integration)
      deliver_error!(404)
    end

    control_access :refresh_installation_access_token, resource: current_integration, allow_integrations: false, allow_user_via_granular_actor: false

    data = receive_with_openapi
    ActiveRecord::Base.connected_to(role: :reading) do

      record = AuthenticationToken
        .active
        .with_unhashed_token(data["token"])
        .first

      deliver_error!(404) unless record

      result = AuthenticationToken.extend_expires_at(record, data["expires_at"], entry_point: :rest_api_integrations_installation_access_tokens)

      if result.success?
        deliver :lightweight_authentication_token_hash, record, token: data["token"], status: 200
      else
        deliver_error!(422, message: result.message)
      end
    end
  end

  post "/app/global/access_tokens", operation_id: :internal, exempt_from_tenant_context_requirement: true do
    @route_owner = "@github/ecosystem-apps"
    enforce_internal_access!

    control_access :create_integration_installation_global_token,
      resource: current_integration,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      disable_conditional_access_policies: !GitHub.flipper[:api_integrations_endpoint_uses_cap].enabled?(current_integration) # rubocop:todo GitHub/DoNotSkipCapAccessAllowed

    data = receive_with_schema("global-app-token", "create")

    ActiveRecord::Base.connected_to(role: :reading) do
      target = User.where(id: data["target_id"]).or(User.where(login: data["target"])).take
      record_or_404(target)

      repos_fetch_result = SiteScopedIntegrationInstallation::RepositoryFetcher.fetch(
        target,
        repository_ids: data.fetch("repository_ids", []),
        repository_names: data.fetch("repositories", []),
        visibility: data["repo_visibility"],
      )
      if repos_fetch_result.failed?
        deliver_error!(422, message: repos_fetch_result.error)
      end

      repositories = repos_fetch_result.repositories
      permissions = data.fetch("permissions", {})

      token, record = generate_site_scoped_token(current_integration, target, repositories, permissions, data)

      deliver :lightweight_authentication_token_hash, record, status: 201, token: token, valid_after: record.valid_after
    end
  end

  get "/organizations/:organization_id/installation", operation_id: "apps/get-org-installation", resolve_tenant_context: :rtc_for_organization do
    org = find_org!
    installation = find_installation_on_user!(org)

    control_access :read_integration_installations,
      resource: installation,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    GitHub::PrefillAssociations.prefill_associations(installation, :integration, available_records: [current_integration])
    deliver :installation_hash, installation
  end

  get "/repositories/:repository_id/installation", operation_id: "apps/get-repo-installation" do
    # The `this_repo` finder helper only applies in the
    # cases where the path is using the name with owner as
    # part of the path.
    repo = params.key?("repository_id") ? current_repo : this_repo

    installation = find_installation_for_repository!(repo)
    control_access :read_integration_installations,
      resource: installation,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    GitHub::PrefillAssociations.prefill_associations(installation, :integration, available_records: [current_integration])
    deliver :installation_hash, installation
  end

  get "/user/:user_id/installation", operation_id: "apps/get-user-installation" do
    control_access :read_integration_installations,
      resource: current_integration,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    user = find_user!
    installation = find_installation_on_user!(user)

    GitHub::PrefillAssociations.prefill_associations(installation, :integration, available_records: [current_integration])
    deliver :installation_hash, installation
  end

  # Fetch the deliveries of the hook associated with the app
  get "/app/hook/deliveries", operation_id: "apps/list-webhook-deliveries" do
    control_access :read_integration_hook_deliveries, resource: current_integration, allow_integrations: false, allow_user_via_granular_actor: false

    hook = current_integration.hook
    record_or_404(hook)

    ensure_data_satisfies_schema!(request.GET, "integration", "deliveries")

    safe_params = params.slice(:cursor, :per_page, :since, :until, :status, :status_code,
                               :events, :redelivery, :guid, :repo_id, :installation_id)

    # filtering is only allowed if the feature flag is on
    unless GitHub.flipper[:hook_deliveries_api_filtering].enabled?(hook.installation_target)
      disallowed_filters = safe_params.except("cursor").except("per_page")
      if disallowed_filters.any?
        error_messages = disallowed_filters.keys.map { |k| "\"#{k}\" is not a permitted key." }.join("\n")
        deliver_error! 422, message: "Invalid request.\n\n#{error_messages}"
      end
    end

    if safe_params[:repo_id]
      repo = Repository.find_by(id: safe_params[:repo_id])
      deliver_error!(404) unless repo
      deliver_error!(404) unless current_integration.installations.with_repository(repo).present?
    end

    if safe_params[:installation_id] &&
        !current_integration.installations.exists?(id: safe_params[:installation_id])
      deliver_error!(404)
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

  # Get a single delivery for the hook associated with the app
  get "/app/hook/deliveries/:delivery_id", operation_id: "apps/get-webhook-delivery" do
    control_access :read_integration_hook_deliveries, resource: current_integration, allow_integrations: false, allow_user_via_granular_actor: false

    hook = current_integration.hook
    record_or_404(hook)

    ensure_data_satisfies_schema!(request.GET, "integration", "delivery")

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
  post "/app/hook/deliveries/:delivery_id/attempts", operation_id: "apps/redeliver-webhook-delivery" do
    control_access :redeliver_integration_hook_delivery, resource: current_integration, allow_integrations: false, allow_user_via_granular_actor: false

    hook = current_integration.hook
    record_or_404(hook)

    receive_with_schema("integration", "redelivery")

    hook_client = HookDeliveriesClient.new(hook.hookshot_parent_id)

    status, body = hook_client.delivery_for_hook(params[:delivery_id], hook.id, {})
    GitHub.dogstats.increment("webhooks_redelivery_attempted", tags: ["method: api", "type: app"])
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

  # Update the app's webhook config
  verbs :patch, :post, "/app/hook/config", operation_id: "apps/update-webhook-config-for-app" do
    control_access :modify_integration_hook_config, resource: current_integration, allow_integrations: false, allow_user_via_granular_actor: false

    hook = current_integration.hook
    record_or_404(hook)
    data = receive_with_schema("hook-config", "update")
    hook.partial_config = data

    if hook.save
      deliver_raw hook.masked_config
    else
      deliver_error 400, message: hook.errors.full_messages
    end
  end

  # get the app's webhook config
  get "/app/hook/config", operation_id: "apps/get-webhook-config-for-app" do
    control_access :read_integration_hook_config, resource: current_integration, allow_integrations: false, allow_user_via_granular_actor: false

    hook = current_integration.hook
    record_or_404(hook)
    deliver_raw hook.masked_config
  end

  # Internal: Resolve tenant context a destroyable installation in API route
  # via :installation_id.
  #
  # Returns an Business or nil.
  def rtc_for_destroyable_installation
    installation = find_destroyable_installation
    installation&.resolve_tenant
  end

  # Internal: Resolve tenant context for installation in API route via :installation_id.
  #
  # Returns an Business or nil.
  def rtc_for_installation
    installation = ActiveRecord::Base.connected_to(role: :reading) { find_installation }
    installation&.resolve_tenant
  end

  # Internal: Resolve tenant context for the :organization in the API route.
  #
  # Returns an Business or nil.
  def rtc_for_organization
    org = find_org!
    org.business
  end

  private

  def get_site_scoped_installation_override_rate_limit(current_integration, repositories, target)
    # Actions specific logic to allow for overriding the rate limit per repo or use the owner rate limit
    if Apps::Privileged.capable?(:global_app_overrides_rate_limit, app: current_integration)
      if repositories.size != 1 || GitHub.flipper[:override_actions_per_repo_rate_limit].enabled?(repositories.first)
        ActiveRecord::Base.connected_to(role: :reading) do
          current_integration.installations_on(target)&.first&.rate_limit
        end
      end
    end
  end

  def enforce_internal_access!
    return unless GitHub.enforce_internal_api_access?

    should_enforce_access = ::Apps::Privileged.capable?(
      :enforce_internal_access_on_token_generation, app: current_integration
    )

    if should_enforce_access && !GitHub.internal_api_role?
      GitHub.dogstats.increment(
        "api_integrations.enforced_internal_access",
        tags: ["integration:#{current_integration.id}"],
      )
      deliver_error!(403)
    end
  end

  def ip_allowlist_enforceable
    :yes
  end

  def saml_enforceable
    :no
  end

  def emu_ownership_enforceable
    :no
  end

  def two_factor_enforceable
    :no
  end

  def filter(scope)
    if (since = time_param!(:since))
      scope = scope.since(since.getlocal)
    end

    scope
  end

  def find_installation
    current_integration.installations.find_by_id(params[:installation_id])
  end

  def find_installation!
    record_or_404(find_installation)
  end

  def find_destroyable_installation
    installation = find_installation
    return unless installation

    if IntegrationInstallation.target_locked_for_deletion?(installation)
      GitHub.dogstats.increment("uninstall_integration_installation_job.target_locked_for_deletion")
      return nil
    end

    installation
  end

  def find_destroyable_installation!
    record_or_404(find_destroyable_installation)
  end

  def find_installation_for_repository!(repository)
    installation = IntegrationInstallations::Public.on_repository(current_integration, repository)
    record_or_404(installation)
  end

  def find_installation_on_user!(user)
    installation = current_integration.installations.find_by(target: user)
    record_or_404(installation)
  end

  def fetch_repository_ids(data, installation_target)
    GitHub.tracer.in_span("Api::Integrations#fetch_repository_ids", kind: :internal) do |span|
      repository_ids = []

      # Unfortunately, this type-assertion is needed until we turn back
      # on the validation for receive_with_schema
      if data[:repository_ids] && data[:repository_ids].is_a?(Array)
        repository_ids << data[:repository_ids]
      end

      if data[:repositories] && data[:repositories].is_a?(Array)
        found_repository_ids = installation_target.repositories.where(name: data[:repositories]).pluck(:id)

        if found_repository_ids.count != data[:repositories].uniq.count
          deliver_error!(422, message: ScopedIntegrationInstallation::Permissions::Result::HUMAN_READABLE_REASONS[:repositories_not_available_to_target])
        end

        repository_ids << found_repository_ids
      end

      span.set_attribute("gh.installation.repositories.count", repository_ids.count)
      repository_ids.flatten.map(&:to_i).uniq
    end
  end

  def per_page(limit)
    return DEFAULT_PER_PAGE unless limit
    [limit.to_i, MAX_PER_PAGE].min
  end

  def should_generate_scoped_token?(repository_ids, data, installation)
    repository_ids.any? || scoped_permissions_requested?(installation, data)
  end

  def should_calculate_valid_after?(integration, installation)
    if installation.is_a?(ScopedIntegrationInstallation)
      GitHub.flipper[:valid_after_for_scoped_installations].enabled?(integration)
    else
      GitHub.flipper[:valid_after_for_regular_installations].enabled?(integration)
    end
  end

  def requested_repository_selection(repository_ids, data)
    return "none" unless scoped_token_repository_param?(data)
    return "empty" if repository_ids.empty?
    "selected"
  end

  def scoped_token_repository_param?(data)
    data[:repositories] || data[:repository_ids]
  end

  def repository_selection(installation)
    installation.installed_on_all_repositories? ? "all" : "selected"
  end

  def permissions_for(installation)
    installation_type = installation.class.name.demodulize.underscore
    memoization_enabled = GitHub.flipper[:api_integrations_permissions_for_memoization].enabled?
    tags = ["installation_type:#{installation_type}", "memoization_enabled:#{memoization_enabled}"]

    hash = GitHub.dogstats.distribution_time("api_integrations.permissions_for", tags: tags) do
      if memoization_enabled
        @permissions_for ||= {}
        key = "#{installation_type}_#{installation.id}"
        @permissions_for[key] ||= fetch_permissions_for(installation)
      else
        fetch_permissions_for(installation)
      end
    end

    unless installation.target.feature_enabled?(:enterprise_app_installation_management)
      return hash.except(*Business::Resources.subject_types)
    end

    hash
  end

  def fetch_permissions_for(installation)
    installation.instance_of?(IntegrationInstallation) ? installation.permissions_or_cached_permissions : installation.permissions
  end

  def single_file_permission?(installation)
    permissions_for(installation).present? && permissions_for(installation).keys.include?("single_file")
  end

  def entry_point_scope_type(repository_ids, installation, data)
    scoped_permissions = scoped_permissions_requested?(installation, data)
    scoped_repos = !repository_ids&.empty?

    if scoped_permissions && scoped_repos
      :SCOPE_TYPE_REPO_AND_PERMISSION
    elsif scoped_permissions
      :SCOPE_TYPE_PERMISSION
    elsif scoped_repos
      :SCOPE_TYPE_REPO
    else
      :SCOPE_TYPE_UNKNOWN
    end
  end

  # Internal: Redirect the request to the repository's new location.
  #
  # block - A block that returns the path to use for the redirect. The block
  #         receives the following arguments to assist in constructing the
  #         redirect path:
  #         :path            - A String representing the full path for this
  #                            request.
  #         :requested_nwo   - A String representing the repository
  #                            name-with-owner that this request is attempting
  #                            to access.
  #         :redirected_repo - The relocated Repository (that previously existed
  #                            at the requested name-with-owner location).
  #
  # Halts with a redirect if the requested repository has relocated (e.g., if it
  #   has been renamed, if it has been transferred, etc.).
  # Halts with a 404 if the request lacks permission to access the relocated
  #   repository.
  # Returns nothing.
  def redirect_to_new_repo_location_or_404!(&block)
    redirected_repo = find_redirected_repo_from_path

    env[GitHub::Routers::Api::ThisRepositoryKey] = redirected_repo

    if access_allowed?(:follow_repo_redirect, resource: redirected_repo, current_integration: current_integration, allow_integrations: true, allow_user_via_granular_actor: true)
      redirect_path =
        block.call(request.fullpath, repo_nwo_from_path, redirected_repo)

      deliver_redirect! \
        api_url(redirect_path), status: permanent_redirect_status_code
    else
      deliver_error!(missing_repository_status_code, **missing_repository_options)
    end
  end

  def generate_site_scoped_token(integration, target, repositories, permissions, data)
    grant_packages_permissions = Apps::Privileged.capable?(:manage_packages_permissions, app: current_integration)
    extended_permissions = data.fetch("extended_permissions", {})
    rate_limit = get_site_scoped_installation_override_rate_limit(current_integration, repositories, target)

    entry_point = Permissions::Service::EntryPoint.build(
      :rest_api_integrations_generate_site_scoped_token,
      target: target,
      actor_owner: integration,
    )
    result = SiteScopedIntegrationInstallation::Creator.perform_with_cache(
      integration,
      target,
      repositories: repositories,
      permissions: permissions,
      extended_permissions: extended_permissions,
      should_grant_packages_permissions: grant_packages_permissions,
      rate_limit: rate_limit,
      entry_point: entry_point,
    )

    if result.failed?
      deliver_error!(422, message: result.error)
    end

    installation = result.installation
    record, token = AuthenticationToken.create_for(installation, code_path: CODEPATH_CREATE_GLOBAL_TOKEN)

    if GitHub.flipper[:valid_after_for_site_scoped_installations].enabled?(integration)
      record.valid_after = valid_after_for(installation, result: result)
    end

    # TODO: Consider removing this once valid_after is fully rolled out.
    # After saving the new token we want to set the last write gtids/timestamps in the
    # cache, so the api DatabaseSelection can use the write DB for newly
    # created tokens and avoid issues due to replication lag.
    DatabaseSelector::LastOperations.from_token(token).store_latest_writes

    [token, record]
  end

  def generate_scoped_token(installation, repository_ids, permissions, data, entry_point:)
    GitHub.tracer.in_span("Api::Integrations#generate_scoped_token", kind: :internal) do |span|
      repositories = if repository_ids.empty? && installation.installed_on_all_repositories?
        repository_selection = ScopedIntegrationInstallation::Creator::INSTALL_ON_ALL_REPOSITORIES
        span.set_attribute("gh.installation.repository_selection", repository_selection.to_s)

        repository_selection
      elsif repository_ids.empty?
        span.set_attribute("gh.installation.repository_selection", "installation.repositories")
        ScopedIntegrationInstallation::Creator::INSTALL_ON_ALL_SELECTED_REPOSITORIES
      else
        span.set_attribute("gh.installation.repository_selection", "selected_repositories")
        GitHub.dogstats.histogram("api.integrations.generate_scoped_token.repositories_requested", repository_ids.count)
        Repository.where(id: repository_ids)
      end

      repositories_were_requested = repositories.is_a?(ActiveRecord::Relation)
      permissions_were_requested  = permissions.present?

      GitHub.dogstats.increment("api.integrations.generate_scoped_token", tags: [
        "repositories_requested:#{repositories_were_requested}",
        "permissions_requested:#{permissions_were_requested}"
      ])

      result = ScopedIntegrationInstallation::Creator.perform_with_cache(
        installation, repositories: repositories, permissions: permissions, log_data: log_data, entry_point: entry_point,
      )

      if GitHub.flipper[:api_integrations_access_token_scoped_logging].enabled?(installation)
        log_details_of_scoped_token_request(result, installation, data: data, permissions: permissions)
      end

      result
    end
  end

  def valid_after_for(installation, result: nil)
    using_cached_installation = result.present? ? result.found_cached? : false
    TokenValidAfterManager.new(installation, using_cached_installation: using_cached_installation).valid_after
  end

  def respond_with_lightweight_authentication_token?
    ::Apps::Privileged.capable?(:can_receive_lightweight_access_token_response, app: current_integration)
  end

  # Internal: wrap the given block by connecting to either the primary or read
  # replicas based on whether the given permissions exist.
  #
  # Scoped installation tokens are written to the database so we should
  # break out of the read-from-replica connection to make sure we use the
  # primary to read our own write.
  #
  # Returns nothing.
  def with_master_or_replica(permissions)
    return unless block_given?

    role = permissions&.empty? ? :writing : :reading

    GitHub.dogstats.increment("api.integrations.access_tokens.create.with_master_or_replica", tags: ["role:#{role}"])

    ActiveRecord::Base.connected_to(role: role) do
      yield
    end
  end

  # Custom validator helper for POST /app/installations/:installation_id/access_tokens
  #
  # While the built-in JSON schema validator is disabled on purpose, we still want to
  # perform some basic type validations in order to prevent them to bubble up as 5XXs
  #
  # REF: https://github.com/github/ecosystem-apps/issues/1222
  def validate_access_token_request_payload!(data)
    return unless data[:permissions].present?

    if !data[:permissions].is_a?(Hash)
      deliver_error!(422, message: INVALID_PERMISSIONS_FORMAT_MSG)
    end

    data[:permissions].each do |_permission, action|
      unless VALID_PERMISSIONS_ACTIONS.include?(action.to_s)
        deliver_error!(422, message: INVALID_PERMISSIONS_ACTIONS_MSG)
      end
    end
  end

  # Temporary validation until OpenAPI schema is enabled for the "apps/create-installation-access-token" operation.
  def validate_repository_names!(names)
    return if names.blank?

    if Array.wrap(names).any? { |name| name =~ EntityName::INVALID_CHARACTERS_REGEX }
      deliver_error!(422, message: INVALID_REPOSITORY_NAME_MSG)
    end
  end

  def scoped_permissions_requested?(installation, data)
    return false unless data.key?(:permissions)

    begin
      installation_permissions = permissions_for(installation)
      requested_permissions = data["permissions"]

      installation_permissions = IntegrationVersion.new(default_permissions: installation_permissions)
      requested_permissions = IntegrationVersion.new(default_permissions: requested_permissions)

      differ = IntegrationVersion::Differ.perform(old_version: installation_permissions, new_version: requested_permissions)

      changed = log_data[:permissions_changed] = differ.permissions_changed?
      GitHub.dogstats.increment("api.integrations.access_tokens.create.should_generate_scoped_token", tags: ["changed:#{changed}"])

      changed
    rescue ArgumentError
      # Permissions are invalid indicate permissions changed and let permissions
      # error get resolved downstream, result is also indifferent from previous iteration.

      true
    end
  end

  def log_details_of_scoped_token_request(result, installation, data: {}, permissions: {}, creator_version: 1)
    perms_from_replicas = result.failed? ? nil : permissions_for(result.installation)
    # nwo is used only for logging therefore safe to use here.
    repos_from_replicas = result.failed? ? nil : result.installation.repositories.map(&:nwo) # rubocop:disable GitHub/DoNotAllowNameWithOwner
    perms_from_primary = T.let(nil, T.nilable(T::Array[T.nilable(T::Hash[String, Symbol])]))
    repos_from_primary = T.let(nil, T.nilable(T::Array[T.nilable(String)]))

    # login used only for logging therfore safe to use here.
    details = {
      "gh.request_id" => GitHub.context[:request_id],
      "gh.catalog_service" => "github/apps",
      "gh.scoped_token_request.type" => "create",
      "gh.scoped_token_request.creator_version" => creator_version,
      "gh.integration.id" => installation.integration.id,
      "gh.installation.target.id" => installation.target.id,
      "gh.scoped_token_result.found_cached" => result.found_cached?,
      "gh.scoped_token_result.failed" => result.failed?,
      "gh.scoped_token_result.error" => result.error,
      "gh.scoped_token_result.permissions_from_replicas" => perms_from_replicas,
      "gh.scoped_token_result.repositories_from_replicas" => repos_from_replicas,
      "gh.scoped_token_result.installation_id" => result.failed? ? nil : result.installation.id
    }

    details_from_primary = ActiveRecord::Base.connected_to(role: :writing) do
      unless result.failed?
        perms_from_primary = permissions_for(result.installation)
        # nwo used only for logging therefore safe to use here.
        repos_from_primary = result.installation.repositories.map(&:nwo) # rubocop:disable GitHub/DoNotAllowNameWithOwner
      end

      {
        "gh.scoped_token_result.permissions_from_primary" => perms_from_primary,
        "gh.scoped_token_result.repositories_from_primary" => repos_from_primary,
      }
    end

    details["gh.scoped_token_result.grant_replica_conflict"] =
      perms_from_replicas != perms_from_primary ||
      repos_from_replicas != repos_from_primary

    msg = "Creating scoped installation token via "
    version_details =
      if creator_version == 1
        msg += "/app/installations/:installation_id/access_tokens"

        {
          "gh.scoped_token_request.repositories" => data[:repositories],
          "gh.scoped_token_request.repository_ids" => data[:repository_ids],
          "gh.scoped_token_request.permissions" => permissions,
        }
      else
        msg += "/app/installations/:installation_id/access_tokens/scoped"

        repo_refs = []
        has_pr_permissions = T.let(false, T::Boolean)
        has_workflow_permissions = T.let(false, T::Boolean)

        data["repositories"]&.each do |repo|
          repo_ref = repo["id"] || repo["name"]
          repo_refs << repo_ref
          has_pr_permissions = true if repo["pull_requests"].present?
          has_workflow_permissions = true if repo["workflow_runs"].present?
        end

        {
          "gh.scoped_token_request.repositories" => repo_refs,
          "gh.scoped_token_request.any_pr_permissions" => has_pr_permissions,
          "gh.scoped_token_request.any_workflow_permissions" => has_workflow_permissions,
        }
      end

    details_hash = details.merge(details_from_primary).merge(version_details)
    GitHub.logger.info(msg, details_hash)
  end

  def tenant_verification_enforceable
    # Exempt first party apps from tenant verification due to not belonging to any Business.
    Apps::Privileged.capable?(:proxima_first_party_sync, app: current_integration) ? :no : :yes
  end
end
