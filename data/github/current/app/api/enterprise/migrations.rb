# typed: true
# frozen_string_literal: true

class Api::Enterprise::Migrations < Api::Enterprise::App
  # Pre-compute ELM resource mapping at class load time for Sorbet compatibility
  # Auto-discovers all ELM export resources from MonolithTwirp::Elm::{Module}::{Version} namespaces
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
    .freeze

  post "/enterprise/migration/create", operation_id: "enterprise-admin/migration-create", read_from_replicas: true do
    deliver_error! 404 unless GitHub.multi_tenant_enterprise?

    biz = GitHub::CurrentTenant.get

    deliver_error! 404 unless FeatureFlag.vexi.enabled?(:migrations_vnext_api_migrations, biz, default: false)

    control_access :administer_business,
      resource: biz,
      forbid: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error! 401 unless biz.adminable_by?(current_user)

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
      deliver_error!(500, message: "Error creating migration: #{e.twirp_response.error.msg}")
    end

    deliver_raw(migration, status: 201)
  end

  get "/enterprise/migration/list", operation_id: "enterprise-admin/migration-list" do
    deliver_error! 404 unless GitHub.multi_tenant_enterprise?

    biz = GitHub::CurrentTenant.get

    deliver_error! 404 unless FeatureFlag.vexi.enabled?(:migrations_vnext_api_migrations, biz, default: false)

    control_access :administer_business,
      resource: biz,
      forbid: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error! 401 unless biz.adminable_by?(current_user)

    migration_ctx = Mvnd::Migrations::Api::V1::Entities::MigrationContext.new({
      enterprise_id: biz.id,
      github_tenant: biz.slug,
      admin_user_id: current_user.id
    })

    begin
      migrations = GitHub.mvnd_client.list_migrations(migration_ctx)
    rescue Mvnd::TwirpError => e
      deliver_error!(500, message: "Error listing migrations: #{e.twirp_response.error.msg}")
    end

    deliver_raw(migrations, status: 200)
  end

  get "/enterprise/migration/:migration_id/status", operation_id: "enterprise-admin/migration-status" do
    deliver_error! 404 unless GitHub.multi_tenant_enterprise?

    biz = GitHub::CurrentTenant.get

    deliver_error! 404 unless FeatureFlag.vexi.enabled?(:migrations_vnext_api_migrations, biz, default: false)

    control_access :administer_business,
      resource: biz,
      forbid: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error! 401 unless biz.adminable_by?(current_user)

    migration_ctx = Mvnd::Migrations::Api::V1::Entities::MigrationContext.new({
      enterprise_id: biz.id,
      github_tenant: biz.slug,
      admin_user_id: current_user.id,
      migration_id: params[:migration_id].to_i
    })

    begin
      migration = GitHub.mvnd_client.migration_status(migration_ctx)
    rescue Mvnd::TwirpError => e
      deliver_error!(500, message: "Error getting migration status: #{e.twirp_response.error.msg}")
    end

    deliver_raw(migration, status: 200)
  end

  post "/enterprise/migration/:migration_id/abort", operation_id: "enterprise-admin/migration-abort", read_from_replicas: true do
    deliver_error! 404 unless GitHub.multi_tenant_enterprise?

    biz = GitHub::CurrentTenant.get

    deliver_error! 404 unless FeatureFlag.vexi.enabled?(:migrations_vnext_api_migrations, biz, default: false)

    control_access :administer_business,
      resource: biz,
      forbid: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error! 401 unless biz.adminable_by?(current_user)

    migration_ctx = Mvnd::Migrations::Api::V1::Entities::MigrationContext.new({
      enterprise_id: biz.id,
      github_tenant: biz.slug,
      admin_user_id: current_user.id,
      migration_id: params[:migration_id].to_i
    })

    begin
      GitHub.mvnd_client.abort_migration(migration_ctx)
    rescue Mvnd::TwirpError => e
      deliver_error!(500, message: "Error aborting migration: #{e.twirp_response.error.msg}")
    end

    deliver_empty(status: 204)
  end

  post "/enterprise/migration/:migration_id/pause", operation_id: "enterprise-admin/migration-pause", read_from_replicas: true do
    deliver_error! 404 unless GitHub.multi_tenant_enterprise?

    biz = GitHub::CurrentTenant.get

    deliver_error! 404 unless FeatureFlag.vexi.enabled?(:migrations_vnext_api_migrations, biz, default: false)

    control_access :administer_business,
      resource: biz,
      forbid: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error! 401 unless biz.adminable_by?(current_user)

    migration_ctx = Mvnd::Migrations::Api::V1::Entities::MigrationContext.new({
      enterprise_id: biz.id,
      github_tenant: biz.slug,
      admin_user_id: current_user.id,
      migration_id: params[:migration_id].to_i
    })

    begin
      GitHub.mvnd_client.pause_migration(migration_ctx)
    rescue Mvnd::TwirpError => e
      deliver_error!(500, message: "Error pausing migration: #{e.twirp_response.error.msg}")
    end

    deliver_empty(status: 204)
  end

  post "/enterprise/migration/:migration_id/resume", operation_id: "enterprise-admin/migration-resume", read_from_replicas: true do
    deliver_error! 404 unless GitHub.multi_tenant_enterprise?

    biz = GitHub::CurrentTenant.get

    deliver_error! 404 unless FeatureFlag.vexi.enabled?(:migrations_vnext_api_migrations, biz, default: false)

    control_access :administer_business,
      resource: biz,
      forbid: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error! 401 unless biz.adminable_by?(current_user)

    migration_ctx = Mvnd::Migrations::Api::V1::Entities::MigrationContext.new({
      enterprise_id: biz.id,
      github_tenant: biz.slug,
      admin_user_id: current_user.id,
      migration_id: params[:migration_id].to_i
    })

    begin
      GitHub.mvnd_client.resume_migration(migration_ctx)
    rescue Mvnd::TwirpError => e
      deliver_error!(500, message: "Error resuming migration: #{e.twirp_response.error.msg}")
    end

    deliver_empty(status: 204)
  end

  post "/enterprise/migration/events", operation_id: "enterprise-admin/migration-events", read_from_replicas: true do
    deliver_error! 404 unless GitHub.multi_tenant_enterprise?

    biz = GitHub::CurrentTenant.get

    deliver_error! 404 unless FeatureFlag.vexi.enabled?(:migrations_vnext_api_migrations, biz, default: false)

    control_access :administer_business,
      resource: biz,
      forbid: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error! 401 unless biz.adminable_by?(current_user)

    data = receive_with_openapi

    migration_ctx = Mvnd::Migrations::Api::V1::Entities::MigrationContext.new({
      enterprise_id: biz.id,
      github_tenant: biz.slug,
      admin_user_id: current_user.id,
      migration_id: data["migration_id"]
    })

    data["events"]&.each { |event_data| send_event!(migration_ctx, event_data) }

    deliver_empty(status: 202)
  end

  post "/enterprise/migration/resources", operation_id: "enterprise-admin/migration-resources", read_from_replicas: true do
    deliver_error! 404 unless GitHub.multi_tenant_enterprise?

    biz = GitHub::CurrentTenant.get

    deliver_error! 404 unless FeatureFlag.vexi.enabled?(:migrations_vnext_api_migrations, biz, default: false)

    control_access :administer_business,
      resource: biz,
      forbid: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error! 401 unless biz.adminable_by?(current_user)

    data = receive_with_openapi
    migration_ctx = Mvnd::Migrations::Api::V1::Entities::MigrationContext.new({
      enterprise_id: biz.id,
      github_tenant: biz.slug,
      admin_user_id: current_user.id,
      migration_id: data["migration_id"]
    })

    data["resources"]&.each { |resource_data| send_resource!(migration_ctx, resource_data) }

    deliver_empty(status: 202)
  end

  post "/enterprise/migration/create-signed-upload-url", operation_id: "enterprise-admin/migration-create-signed-upload-url", read_from_replicas: true do
    deliver_error! 404 unless GitHub.multi_tenant_enterprise?

    biz = GitHub::CurrentTenant.get

    deliver_error! 404 unless FeatureFlag.vexi.enabled?(:migrations_vnext_api_migrations, biz, default: false)

    control_access :administer_business,
      resource: biz,
      forbid: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error! 401 unless biz.adminable_by?(current_user)

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

    control_access :administer_business,
      resource: biz,
      forbid: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error! 401 unless biz.adminable_by?(current_user)

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
      deliver_error!(500, message: "Error marking resources sent: #{e.twirp_response.error.msg}")
    end

    deliver_empty(status: 204)
  end

  private

  def send_event!(migration_ctx, event_data)
    event_type = event_data["EventDetails"]&.keys&.first
    return unless event_type

    inner_data = event_data.delete("EventDetails")[event_type]
    event_data[event_type.underscore] = inner_data
    event_data["migration_context"] = migration_ctx
    event = Mvnd::Migrations::Api::V1::Event.new(event_data)

    begin
      GitHub.mvnd_client.store_event(event)
    rescue Mvnd::TwirpError => e
      http_status = Twirp::ERROR_CODES_TO_HTTP_STATUS[e.twirp_response.error.code] || 500
      deliver_error!(http_status, message: "Error processing event: #{e.twirp_response.error.msg}")
    end
  end

  def send_resource!(migration_ctx, resource_data)
    resource_type = resource_data["Resource"]&.keys&.first
    return unless resource_type

    inner_data = resource_data["Resource"][resource_type]

    # Map resource types to their correct namespaces
    inner_class = get_resource_class(resource_type)

    inner_object = inner_class.new(inner_data)
    resource = Mvnd::Migrations::Api::V1::Resource.new(
      { resource_type.underscore => inner_object, :migration_context => migration_ctx })

    begin
      GitHub.mvnd_client.create_resource(resource)
    rescue Mvnd::TwirpError => e
      http_status = Twirp::ERROR_CODES_TO_HTTP_STATUS[e.twirp_response.error.code] || 500
      deliver_error!(http_status, message: "Error processing resource: #{e.twirp_response.error.msg}")
    end
  end

  def get_resource_class(resource_type)
    return ELM_RESOURCE_MAPPING[resource_type] if ELM_RESOURCE_MAPPING.key?(resource_type)

    # Default to existing entities namespace for legacy resources
    Mvnd::Migrations::Api::V1::Entities.const_get(resource_type)
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
