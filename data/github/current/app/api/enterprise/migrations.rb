# typed: true
# frozen_string_literal: true

class Api::Enterprise::Migrations < Api::Enterprise::App

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
    inner_class = Mvnd::Migrations::Api::V1.const_get(resource_type)
    inner_object = inner_class.new(inner_data)
    resource = Mvnd::Migrations::Api::V1::Resource.new(
      { resource_type.underscore => inner_object, :migration_context => migration_ctx })

    begin
      GitHub.mvnd_client.create_resource(resource)
    rescue Mvnd::TwirpError
      deliver_error!(500, message: "Error processing resource")
    end
  end
end
