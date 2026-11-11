# typed: true
# frozen_string_literal: true

class Api::Repositories::CustomProperties::OrganizationSchema < Api::App
  include CustomPropertiesCore::Errors
  include ReceiveSchemaWithOpenApi

  # Schema of the properties for a organization
  get "/organizations/:organization_id/properties/schema", operation_id: "orgs/custom-properties-for-repos-get-organization-definitions" do
    org = find_org!

    control_access :read_org_custom_properties,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    track_reader_permissions(org)

    deliver :property_definition_hash, Repositories.domain.custom_properties.get_definitions(org)
  end

  get "/organizations/:organization_id/properties/schema/:custom_property_name", operation_id: "orgs/custom-properties-for-repos-get-organization-definition" do
    org = find_org!

    control_access :read_org_custom_properties,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    track_reader_permissions(org)

    definition = Repositories.domain.custom_properties.get_definition(org, params[:custom_property_name])
    return deliver_error 404 if definition.nil?

    if definition.source_type != "org"
      deliver_error! 422, message: "Cannot access property '#{definition.property_name}'. Property is defined at enterprise level."
    end

    deliver :property_definition_hash, definition
  end

  patch "/organizations/:organization_id/properties/schema", operation_id: "orgs/custom-properties-for-repos-create-or-update-organization-definitions" do
    org = find_org!

    control_access :manage_org_custom_properties_definitions,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    track_manage_definitions_permissions(org)

    data = receive_with_openapi

    begin
      duplicates = data["properties"]
        .map { |definition| definition["property_name"].downcase }
        .tally.select { |_, count| count > 1 }
        .keys

      if duplicates.any?
        names = duplicates.map { |name| "'#{name}'" }.join(", ")
        raise ArgumentError.new "Multiple updates for the same #{"property".pluralize(duplicates.size)} are found: #{names}. Property name uniqueness is case insensitive."
      end

      Repository.transaction do
        data["properties"].each do |definition|
          Repositories.domain.custom_properties.save_definition(org, **definition.symbolize_keys)
        end
      end

      deliver :property_definition_hash, Repositories.domain.custom_properties.get_definitions(org)
    rescue DefinitionLimitReachedError, InvalidDefinition, ArgumentError, DefinitionDeletionAllowValueInUseError => exception
      deliver_error! 422, message: exception.message
    end
  end

  put "/organizations/:organization_id/properties/schema/:custom_property_name", operation_id: "orgs/custom-properties-for-repos-create-or-update-organization-definition" do
    org = find_org!

    control_access :manage_org_custom_properties_definitions,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    track_manage_definitions_permissions(org)

    begin
      data = receive_with_openapi
      definition = Repositories.domain.custom_properties.save_definition(org, **data.symbolize_keys, property_name: params[:custom_property_name])
      deliver :property_definition_hash, definition
    rescue DefinitionLimitReachedError, InvalidDefinition, ArgumentError, DefinitionDeletionAllowValueInUseError => exception
      deliver_error! 422, message: exception.message
    end
  end

  delete "/organizations/:organization_id/properties/schema/:custom_property_name", operation_id: "orgs/custom-properties-for-repos-delete-organization-definition" do
    org = find_org!

    control_access :manage_org_custom_properties_definitions,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    track_manage_definitions_permissions(org)

    begin
      delete_definition = Repositories.domain.custom_properties.delete_definition(org, params[:custom_property_name])
      deliver_error! 404 if delete_definition.nil?
      deliver_empty status: 204
    rescue InvalidDefinition => exception
      deliver_error! 422, message: exception.message
    end
  end

  def track_reader_permissions(org)
    return unless FeatureFlag.vexi.enabled?(:track_org_custom_properties_perms, default: false)

    access_through_org_custom_properties_reader =
      Repositories.domain.custom_properties.can_see_property_definitions?(current_user, org)

    access_through_member_reader = org.resources.members.readable_by?(current_user)

    tag_value = if access_through_org_custom_properties_reader && access_through_member_reader
      "both"
    elsif access_through_org_custom_properties_reader
      "org_props_reader"
    else
      "member_reader"
    end

    GitHub.dogstats.increment("repos.custom_properties_permissions.reader", tags: ["perms:#{tag_value}"])
  end

  def track_manage_definitions_permissions(org)
    return unless FeatureFlag.vexi.enabled?(:track_org_custom_properties_perms, default: false)

    if current_user.try(:can_have_granular_permissions?)
      via_adminable_props = org.resources.organization_custom_properties.adminable_by?(current_user)
      via_org_admin = org.resources.organization_administration.writable_by?(current_user)

      tag_value = if via_adminable_props && via_org_admin
        "both"
      elsif via_adminable_props
        "adminable_props"
      else
        "org_admin"
      end

      GitHub.dogstats.increment("repos.custom_properties_permissions.definitions_mgr", tags: ["perms:#{tag_value}"])
    end
  end
end
