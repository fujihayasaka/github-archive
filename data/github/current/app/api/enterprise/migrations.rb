# typed: true
# frozen_string_literal: true

class Api::Enterprise::Migrations < Api::Enterprise::App
  # Pre-compute ELM resource mapping at class load time for Sorbet compatibility
  # Auto-discovers all ELM export resources from MonolithTwirp::Elm::{Module}::{Version} namespaces.
  # ExportCommitStatusCheck is then pinned to V1: the import path consumes the V1 message schema,
  # while V2 is an export-only type with an incompatible schema that must not overwrite it.
  ELM_RESOURCE_MAPPING = MonolithTwirp::Elm.constants
    .flat_map do |module_name|
      # Get each module constant (e.g., Actions, Organizations, etc.)
      module_const = MonolithTwirp::Elm.const_get(module_name)
      # Find all version constants (V1, V2, V3, etc.) within each module
      module_const.constants.filter_map do |version_name|
        version_module = module_const.const_get(version_name)
        next unless version_name.to_s.start_with?("V") && version_module.is_a?(Module)

        # Within each version namespace, find all Export* classes
        version_module.constants
          .select { |class_name| class_name.to_s.start_with?("Export") }
          .filter_map do |class_name|
            class_const = version_module.const_get(class_name)
            # Map resource name to class: "ExportCommitStatusCheck" => MonolithTwirp::Elm::Actions::V1::ExportCommitStatusCheck
            # Note: If multiple versions have the same resource name, later versions will overwrite earlier ones
            [class_name.to_s, class_const] if class_const.is_a?(Class)
          end
      end.flatten(1) # Flatten the nested arrays from versions
    end
    .to_h # Convert array of [name, class] pairs to hash
    .merge("ExportCommitStatusCheck" => MonolithTwirp::Elm::Actions::V1::ExportCommitStatusCheck)
    .freeze

  post "/enterprise/migration/create", operation_id: "enterprise-admin/migration-create", read_from_replicas: true do
    deliver_error! 404 unless GitHub.multi_tenant_enterprise?

    biz = GitHub::CurrentTenant.get

    deliver_error! 404 unless FeatureFlag.vexi.enabled?(:migrations_vnext_api_migrations, biz, default: false)

    control_access :standard_authorization,
      resource: biz,
      permission: :write_enterprise_live_migrations,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true

    data = receive_with_openapi

    migration_ctx = Mvnd::Migrations::Api::V1::Entities::MigrationContext.new({
      enterprise_id: biz.id,
      github_tenant: biz.slug,
      admin_user_id: current_user.id,
      source_url: data["source_url"]
    })

    begin
      migration = GitHub.mvnd_client.create_migration(migration_ctx, GitHub.url, data["description"], data["repositories"])
    rescue Mvnd::TwirpError => e
      deliver_twirp_error!(e, "Error creating migration: #{e.twirp_response.error.msg}")
    end

    deliver_raw(migration, status: 201)
  end

  get "/enterprise/migration/list", operation_id: "enterprise-admin/migration-list" do
    deliver_error! 404 unless GitHub.multi_tenant_enterprise?

    biz = GitHub::CurrentTenant.get

    deliver_error! 404 unless FeatureFlag.vexi.enabled?(:migrations_vnext_api_migrations, biz, default: false)

    control_access :standard_authorization,
      resource: biz,
      permission: :read_enterprise_live_migrations,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true

    migration_ctx = Mvnd::Migrations::Api::V1::Entities::MigrationContext.new({
      enterprise_id: biz.id,
      github_tenant: biz.slug,
      admin_user_id: current_user.id
    })

    page_size = params[:page_size]
    if page_size && page_size.to_s !~ /\A\d+\z/
      deliver_error! 400, message: "page_size must be a non-negative integer"
    end

    begin
      migrations = GitHub.mvnd_client.list_migrations(migration_ctx,
        page_size: page_size&.to_i,
        page_token: params[:page_token])
    rescue Mvnd::TwirpError => e
      deliver_twirp_error!(e, "Error listing migrations: #{e.twirp_response.error.msg}")
    end

    result = JSON.parse(migrations.to_json)
    result.delete("nextPageToken") if result["nextPageToken"].to_s.empty?

    deliver_raw(result, status: 200)
  end

  get "/enterprise/migration/quota", operation_id: "enterprise-admin/migration-quota" do
    deliver_error! 404 unless GitHub.multi_tenant_enterprise?

    biz = GitHub::CurrentTenant.get

    deliver_error! 404 unless FeatureFlag.vexi.enabled?(:migrations_vnext_api_migrations, biz, default: false)

    control_access :standard_authorization,
      resource: biz,
      permission: :read_enterprise_live_migrations,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true

    begin
      quota = GitHub.mvnd_client.get_migration_quota(biz.id)
    rescue Mvnd::TwirpError => e
      deliver_twirp_error!(e, "Error getting migration quota: #{e.twirp_response.error.msg}")
    end

    result = {
      active: quota.active.to_i,
      maxActive: quota.max_active.to_i,
    }
    result[:backfilling] = quota.backfilling.to_i if quota.has_backfilling?
    result[:maxBackfilling] = quota.max_backfilling.to_i if quota.has_max_backfilling?

    deliver_raw(result, status: 200)
  end

  get "/enterprise/migration/:migration_id/status", operation_id: "enterprise-admin/migration-status" do
    deliver_error! 404 unless GitHub.multi_tenant_enterprise?

    biz = GitHub::CurrentTenant.get

    deliver_error! 404 unless FeatureFlag.vexi.enabled?(:migrations_vnext_api_migrations, biz, default: false)

    control_access :standard_authorization,
      resource: biz,
      permission: :read_enterprise_live_migrations,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true

    migration_ctx = Mvnd::Migrations::Api::V1::Entities::MigrationContext.new({
      enterprise_id: biz.id,
      github_tenant: biz.slug,
      admin_user_id: current_user.id,
      migration_id: params[:migration_id].to_i
    })

    begin
      migration = GitHub.mvnd_client.migration_status(migration_ctx)
    rescue Mvnd::TwirpError => e
      deliver_twirp_error!(e, "Error getting migration status: #{e.twirp_response.error.msg}")
    end

    deliver_raw(migration, status: 200)
  end

  post "/enterprise/migration/:migration_id/abort", operation_id: "enterprise-admin/migration-abort", read_from_replicas: true do
    deliver_error! 404 unless GitHub.multi_tenant_enterprise?

    biz = GitHub::CurrentTenant.get

    deliver_error! 404 unless FeatureFlag.vexi.enabled?(:migrations_vnext_api_migrations, biz, default: false)

    control_access :standard_authorization,
      resource: biz,
      permission: :write_enterprise_live_migrations,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true

    migration_ctx = Mvnd::Migrations::Api::V1::Entities::MigrationContext.new({
      enterprise_id: biz.id,
      github_tenant: biz.slug,
      admin_user_id: current_user.id,
      migration_id: params[:migration_id].to_i
    })

    begin
      GitHub.mvnd_client.abort_migration(migration_ctx)
    rescue Mvnd::TwirpError => e
      deliver_twirp_error!(e, "Error aborting migration: #{e.twirp_response.error.msg}")
    end

    deliver_empty(status: 204)
  end

  post "/enterprise/migration/:migration_id/pause", operation_id: "enterprise-admin/migration-pause", read_from_replicas: true do
    deliver_error! 404 unless GitHub.multi_tenant_enterprise?

    biz = GitHub::CurrentTenant.get

    deliver_error! 404 unless FeatureFlag.vexi.enabled?(:migrations_vnext_api_migrations, biz, default: false)

    control_access :standard_authorization,
      resource: biz,
      permission: :write_enterprise_live_migrations,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true

    migration_ctx = Mvnd::Migrations::Api::V1::Entities::MigrationContext.new({
      enterprise_id: biz.id,
      github_tenant: biz.slug,
      admin_user_id: current_user.id,
      migration_id: params[:migration_id].to_i
    })

    begin
      GitHub.mvnd_client.pause_migration(migration_ctx)
    rescue Mvnd::TwirpError => e
      deliver_twirp_error!(e, "Error pausing migration: #{e.twirp_response.error.msg}")
    end

    deliver_empty(status: 204)
  end

  post "/enterprise/migration/:migration_id/resume", operation_id: "enterprise-admin/migration-resume", read_from_replicas: true do
    deliver_error! 404 unless GitHub.multi_tenant_enterprise?

    biz = GitHub::CurrentTenant.get

    deliver_error! 404 unless FeatureFlag.vexi.enabled?(:migrations_vnext_api_migrations, biz, default: false)

    control_access :standard_authorization,
      resource: biz,
      permission: :write_enterprise_live_migrations,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true

    migration_ctx = Mvnd::Migrations::Api::V1::Entities::MigrationContext.new({
      enterprise_id: biz.id,
      github_tenant: biz.slug,
      admin_user_id: current_user.id,
      migration_id: params[:migration_id].to_i
    })

    begin
      GitHub.mvnd_client.resume_migration(migration_ctx)
    rescue Mvnd::TwirpError => e
      deliver_twirp_error!(e, "Error resuming migration: #{e.twirp_response.error.msg}")
    end

    deliver_empty(status: 204)
  end

  post "/enterprise/migration/events", operation_id: "enterprise-admin/migration-events", read_from_replicas: true do
    deliver_error! 404 unless GitHub.multi_tenant_enterprise?

    biz = GitHub::CurrentTenant.get

    deliver_error! 404 unless FeatureFlag.vexi.enabled?(:migrations_vnext_api_migrations, biz, default: false)

    control_access :standard_authorization,
      resource: biz,
      permission: :write_enterprise_live_migrations,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true

    data = receive_with_openapi

    migration_ctx = Mvnd::Migrations::Api::V1::Entities::MigrationContext.new({
      enterprise_id: biz.id,
      github_tenant: biz.slug,
      admin_user_id: current_user.id,
      migration_id: data["migration_id"]
    })

    GitHub.dogstats.distribution("enterprise.elm_migration.items_per_request", data["events"]&.length || 0, tags: ["endpoint:events"])

    events = data["events"]&.map { |event_data| build_event!(migration_ctx, event_data) }
    if events&.any?
      begin
        response = GitHub.mvnd_client.store_events(events)
        if response.failures.any?
          first_failure = response.failures.first
          status = first_failure.retryable ? 500 : 400
          failed_ids = response.failures.map(&:resource_id)
          all_event_ids = events.map(&:event_id)
          halt deliver_raw({
            message: "Error processing event: #{first_failure.reason}",
            status: status.to_s,
            failed_event_ids: failed_ids,
            succeeded_event_ids: all_event_ids - failed_ids
          }, status: status)
        end
      rescue Mvnd::TwirpError => e
        deliver_twirp_error!(e, "Error processing event: #{e.twirp_response.error.msg}")
      end
    end

    deliver_empty(status: 202)
  end

  post "/enterprise/migration/resources", operation_id: "enterprise-admin/migration-resources", read_from_replicas: true do
    deliver_error! 404 unless GitHub.multi_tenant_enterprise?

    biz = GitHub::CurrentTenant.get

    deliver_error! 404 unless FeatureFlag.vexi.enabled?(:migrations_vnext_api_migrations, biz, default: false)

    control_access :standard_authorization,
      resource: biz,
      permission: :write_enterprise_live_migrations,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true

    data = receive_with_openapi
    migration_ctx = Mvnd::Migrations::Api::V1::Entities::MigrationContext.new({
      enterprise_id: biz.id,
      github_tenant: biz.slug,
      admin_user_id: current_user.id,
      migration_id: data["migration_id"]
    })

    GitHub.dogstats.distribution("enterprise.elm_migration.items_per_request", data["resources"]&.length || 0, tags: ["endpoint:resources"])

    resource_id_list = []
    resources = data["resources"]&.map do |resource_data|
      resource, resource_id = build_resource!(migration_ctx, resource_data)
      resource_id_list << resource_id.to_s
      resource
    end
    if resources&.any?
      begin
        response = GitHub.mvnd_client.create_resources(resources)
        if response.failures.any?
          first_failure = response.failures.first
          status = first_failure.retryable ? 500 : 400
          failed_ids = response.failures.map(&:resource_id)
          halt deliver_raw({
            message: "Error processing resource: #{first_failure.reason}",
            status: status.to_s,
            failed_resource_ids: failed_ids,
            succeeded_resource_ids: resource_id_list - failed_ids
          }, status: status)
        end
      rescue Mvnd::TwirpError => e
        deliver_twirp_error!(e, "Error processing resource: #{e.twirp_response.error.msg}")
      end
    end

    deliver_empty(status: 202)
  end

  post "/enterprise/migration/create-signed-upload-url", operation_id: "enterprise-admin/migration-create-signed-upload-url", read_from_replicas: true do
    deliver_error! 404 unless GitHub.multi_tenant_enterprise?

    biz = GitHub::CurrentTenant.get

    deliver_error! 404 unless FeatureFlag.vexi.enabled?(:migrations_vnext_api_migrations, biz, default: false)

    control_access :standard_authorization,
      resource: biz,
      permission: :write_enterprise_live_migrations,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true

    data = receive_with_openapi
    migration_ctx = Mvnd::Migrations::Api::V1::Entities::MigrationContext.new({
      enterprise_id: biz.id,
      github_tenant: biz.slug,
      admin_user_id: current_user.id,
      migration_id: data["migration_id"]
    })

    response = get_asset_upload_url_and_asset_blob_path!(migration_ctx, data["resource_id"], data["content_type"], data["asset_kind"])

    # Note: The response contains both attachment/asset signed URL, doing this to not break compatibility,
    # after we fix this on the client side, we can remove the attachment_upload_url. Assets better encapsulate
    # the concept of uploadable assets as attachments only refers to attachments to issues, PRs, etc. while assets
    # better represents any kind of uploadable resource.
    deliver_raw({ "attachment_upload_url" => response.signed_url, "asset_upload_url" => response.signed_url, "asset_blob_path" => response.asset_blob_path })
  end

  post "/enterprise/migration/:migration_id/mark-all-resources-sent", operation_id: "enterprise-admin/migration-mark-all-resources-sent", read_from_replicas: true do
    deliver_error! 404 unless GitHub.multi_tenant_enterprise?

    biz = GitHub::CurrentTenant.get

    deliver_error! 404 unless FeatureFlag.vexi.enabled?(:migrations_vnext_api_migrations, biz, default: false)

    control_access :standard_authorization,
      resource: biz,
      permission: :write_enterprise_live_migrations,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true

    data = receive_with_openapi

    migration_ctx = Mvnd::Migrations::Api::V1::Entities::MigrationContext.new({
      enterprise_id: biz.id,
      github_tenant: biz.slug,
      admin_user_id: current_user.id,
      migration_id: params[:migration_id].to_i
    })

    begin
      GitHub.mvnd_client.mark_all_resources_sent(migration_ctx, data["repository_nwo"])
    rescue Mvnd::TwirpError => e
      deliver_twirp_error!(e, "Error marking resources sent: #{e.twirp_response.error.msg}")
    end

    deliver_empty(status: 204)
  end

  get "/enterprise/migration/:migration_id/nodes", operation_id: "enterprise-admin/migration-list-migration-nodes", read_from_replicas: true do
    deliver_error! 404 unless GitHub.multi_tenant_enterprise?

    biz = GitHub::CurrentTenant.get

    deliver_error! 404 unless FeatureFlag.vexi.enabled?(:migrations_vnext_api_migrations, biz, default: false)

    control_access :standard_authorization,
      resource: biz,
      permission: :read_enterprise_live_migrations,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true

    migration_ctx = Mvnd::Migrations::Api::V1::Entities::MigrationContext.new({
      enterprise_id: biz.id,
      github_tenant: biz.slug,
      admin_user_id: current_user.id,
      migration_id: params[:migration_id].to_i
    })

    begin
      response = GitHub.mvnd_client.list_migration_nodes(migration_ctx,
        params[:repository_nwo],
        params[:state],
        params[:origin],
        params[:page_size]&.to_i,
        params[:after])
      deliver_raw(response)
    rescue Mvnd::TwirpError => e
      http_status = Twirp::ERROR_CODES_TO_HTTP_STATUS[e.twirp_response.error.code] || 500
      deliver_error!(http_status, message: "Error listing nodes: #{e.twirp_response.error.msg}")
    end
  end

  post "/enterprise/migration/:migration_id/update-repository-state", operation_id: "enterprise-admin/migration-update-repository-state", read_from_replicas: true do
    deliver_error! 404 unless GitHub.multi_tenant_enterprise?

    biz = GitHub::CurrentTenant.get

    deliver_error! 404 unless FeatureFlag.vexi.enabled?(:migrations_vnext_api_migrations, biz, default: false)

    control_access :standard_authorization,
      resource: biz,
      permission: :write_enterprise_live_migrations,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true

    data = receive_with_openapi

    migration_ctx = Mvnd::Migrations::Api::V1::Entities::MigrationContext.new({
      enterprise_id: biz.id,
      github_tenant: biz.slug,
      admin_user_id: current_user.id,
      migration_id: params[:migration_id].to_i
    })

    begin
      # Note historically we did not track destination_nwo anywhere on the server side, except the specific repository
      # resource and repository_nwo is the "source"/GHES repository name, so we added it here to improve observability.
      GitHub.mvnd_client.update_repository_state(migration_ctx, data["repository_nwo"], data["state"], destination_nwo: data["destination_nwo"])
    rescue Mvnd::TwirpError => e
      deliver_twirp_error!(e, "Error updating repository state: #{e.twirp_response.error.msg}")
    end

    deliver_empty(status: 204)
  end

  post "/enterprise/migration/:migration_id/mark-repository-locked", operation_id: "enterprise-admin/migration-mark-repository-locked", read_from_replicas: true do
    deliver_error! 404 unless GitHub.multi_tenant_enterprise?

    biz = GitHub::CurrentTenant.get

    deliver_error! 404 unless FeatureFlag.vexi.enabled?(:migrations_vnext_api_migrations, biz, default: false)

    control_access :standard_authorization,
      resource: biz,
      permission: :write_enterprise_live_migrations,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true

    data = receive_with_openapi

    migration_ctx = Mvnd::Migrations::Api::V1::Entities::MigrationContext.new({
      enterprise_id: biz.id,
      github_tenant: biz.slug,
      admin_user_id: current_user.id,
      migration_id: params[:migration_id].to_i
    })

    begin
      GitHub.mvnd_client.mark_repository_locked(migration_ctx, data["repository_nwo"])
    rescue Mvnd::TwirpError => e
      deliver_twirp_error!(e, "Error marking repository locked: #{e.twirp_response.error.msg}")
    end

    deliver_empty(status: 204)
  end

  post "/enterprise/migration/:migration_id/report-git-sync", operation_id: "enterprise-admin/migration-report-git-sync", read_from_replicas: true do
    deliver_error! 404 unless GitHub.multi_tenant_enterprise?

    biz = GitHub::CurrentTenant.get

    deliver_error! 404 unless FeatureFlag.vexi.enabled?(:migrations_vnext_api_migrations, biz, default: false)

    control_access :standard_authorization,
      resource: biz,
      permission: :write_enterprise_live_migrations,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true

    data = receive_with_openapi

    migration_ctx = Mvnd::Migrations::Api::V1::Entities::MigrationContext.new({
      enterprise_id: biz.id,
      github_tenant: biz.slug,
      admin_user_id: current_user.id,
      migration_id: params[:migration_id].to_i
    })

    # Convert Unix timestamps to Google::Protobuf::Timestamp
    start_time = Google::Protobuf::Timestamp.new(seconds: data["iteration_start_time"].to_i, nanos: 0)
    end_time = Google::Protobuf::Timestamp.new(seconds: data["iteration_end_time"].to_i, nanos: 0)

    begin
      GitHub.mvnd_client.report_git_sync(
        migration_ctx,
        data["repository_nwo"],
        start_time,
        end_time,
        data["git_source"],
        data["success"],
        data["error_message"],
        error_messages: data.fetch("error_messages", []),
        additional_errors: data.fetch("additional_errors", false)
      )
    rescue Mvnd::TwirpError => e
      deliver_error!(500, message: "Error reporting git sync: #{e.twirp_response.error.msg}")
    end

    deliver_empty(status: 204)
  end

  private

  def build_event!(migration_ctx, event_data)
    event_details = event_data["EventDetails"]
    if !event_details.is_a?(Hash) || event_details.empty?
      deliver_error!(400, message: "Missing or empty EventDetails wrapper key in event payload")
    end

    event_type = event_details.keys.first
    inner_data = event_data.delete("EventDetails")[event_type]
    if inner_data.nil? || !inner_data.is_a?(Hash)
      deliver_error!(400, message: "Malformed EventDetails payload")
    end

    event_data[event_type.underscore] = inner_data
    event_data["migration_context"] = migration_ctx

    begin
      Mvnd::Migrations::Api::V1::Event.new(event_data)
    rescue Google::Protobuf::TypeError, RangeError, ArgumentError => e
      deliver_error!(400, message: e.message)
    end
  end

  def build_resource!(migration_ctx, resource_data)
    resource_wrapper = resource_data["Resource"]
    if !resource_wrapper.is_a?(Hash) || resource_wrapper.empty?
      deliver_error!(400, message: "Missing or empty Resource wrapper key in resource payload")
    end

    resource_type = resource_wrapper.keys.first
    inner_data = resource_data["Resource"][resource_type]

    inner_class = get_resource_class!(resource_type)

    begin
      inner_object = inner_class.new(inner_data)
      resource = Mvnd::Migrations::Api::V1::Resource.new({
        resource_type.underscore => inner_object,
        :migration_context => migration_ctx,
        :origin => resource_data["origin"]
      })
      [resource, inner_data["resource_id"]]
    rescue Google::Protobuf::TypeError, RangeError, ArgumentError => e
      deliver_error!(400, message: e.message)
    end
  end

  def deliver_twirp_error!(e, message)
    error = e.twirp_response.error
    metadata = error.meta || {}

    # Check for terminal state metadata
    if metadata["terminal"] == "true"
      # Override status to 422 and set migration status headers
      response.headers["X-Migration-Status"] = metadata["migration_status"] if metadata["migration_status"]
      response.headers["X-Migration-Terminated"] = "true"
      deliver_error!(422, message: message)
    else
      # Standard Twirp error handling
      http_status = Twirp::ERROR_CODES_TO_HTTP_STATUS[error.code] || 500
      deliver_error!(http_status, message: message)
    end
  end

  def get_resource_class!(resource_type)
    return ELM_RESOURCE_MAPPING[resource_type] if ELM_RESOURCE_MAPPING.key?(resource_type)

    begin
      resolve_entity_class!(resource_type)
    rescue NameError
      deliver_error!(400, message: "Unknown resource type: #{resource_type}")
    end
  end

  # Safely resolve a resource type to a class within the Entities namespace.
  # Prevents namespace traversal attacks (e.g., "Progeny::Command") by:
  # 1. Rejecting qualified constant names containing "::"
  # 2. Using inherit: false to only resolve constants directly defined in
  #    the Entities module, not from ancestors like Object
  def resolve_entity_class!(resource_type)
    if resource_type.nil? || resource_type.empty?
      raise NameError, "Invalid resource type: #{resource_type.inspect}"
    end

    if resource_type.include?("::")
      raise NameError, "Invalid resource type: #{resource_type}"
    end

    unless Mvnd::Migrations::Api::V1::Entities.const_defined?(resource_type, false)
      raise NameError, "Unknown resource type: #{resource_type}"
    end

    Mvnd::Migrations::Api::V1::Entities.const_get(resource_type, false)
  end

  def get_asset_upload_url_and_asset_blob_path!(migration_ctx, resource_id, content_type, asset_kind)
    request = Mvnd::Migrations::Api::V1::GenerateSignedUploadURLRequest.new(
      resource_id: resource_id,
      content_type: content_type,
      asset_kind: asset_kind,
      migration_context: migration_ctx
    )

    begin
      GitHub.mvnd_client.generate_signed_upload_url(request)
    rescue Mvnd::TwirpError
      deliver_error!(500, message: "Error creating the asset upload url or the asset blob path")
    end
  end
end
