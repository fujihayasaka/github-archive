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

  post "/enterprise/migration/events", operation_id: "enterprise-admin/migration-events" do
    deliver_error! 404 unless GitHub.multi_tenant_enterprise?

    biz = GitHub::CurrentTenant.get

    deliver_error! 404 unless GitHub.flipper[:migrations_vnext_api_migrations].enabled?(biz)

    control_access :administer_business,
      resource: biz,
      forbid: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error! 401 unless biz.adminable_by?(current_user)

    data = receive_with_openapi

    migration_ctx = Mvnd::Migrations::Api::V1::MigrationContext.new({
      enterprise_id: biz.id,
      admin_user_id: current_user.id,
      source_url: data["source_url"]
    })

    data["events"]&.each { |event_data| send_event!(migration_ctx, event_data) }

    deliver_empty(status: 202)
  end

  post "/enterprise/migration/resources", operation_id: "enterprise-admin/migration-resources" do
    deliver_error! 404 unless GitHub.multi_tenant_enterprise?

    biz = GitHub::CurrentTenant.get

    deliver_error! 404 unless GitHub.flipper[:migrations_vnext_api_migrations].enabled?(biz)

    control_access :administer_business,
      resource: biz,
      forbid: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error! 401 unless biz.adminable_by?(current_user)

    data = receive_with_openapi
    migration_ctx = Mvnd::Migrations::Api::V1::MigrationContext.new({
      enterprise_id: biz.id,
      admin_user_id: current_user.id,
      source_url: data["source_url"]
    })

    data["resources"]&.each { |resource_data| send_resource!(migration_ctx, resource_data) }

    deliver_empty(status: 202)
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
    rescue Mvnd::TwirpError
      deliver_error!(500, message: "Error processing event")
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
    rescue Mvnd::TwirpError
      deliver_error!(500, message: "Error processing resource")
    end
  end

  def get_resource_class(resource_type)
    return ELM_RESOURCE_MAPPING[resource_type] if ELM_RESOURCE_MAPPING.key?(resource_type)

    # Default to existing entities namespace for legacy resources
    Mvnd::Migrations::Api::V1::Entities.const_get(resource_type)
  end

  def generate_signed_upload_url!(migration_ctx, resource_id, content_type, asset_kind)
    request = Mvnd::Migrations::Api::V1::GenerateSignedUploadURLRequest.new(
      resource_id: resource_id,
      content_type: content_type,
      asset_kind: asset_kind,
      migration_context: migration_ctx
    )

    begin
      GitHub.mvnd_client.generate_signed_upload_url(request)
    rescue Mvnd::TwirpError
      deliver_error!(500, message: "Error creating attachment upload url")
    end
  end
end
