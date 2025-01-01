# typed: strict
# frozen_string_literal: true

class Businesses::PropertyDefinitionNameCheckController < Businesses::BusinessController
  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::IamAbilities,
  only: [:show]

  MAX_DISPLAYED_USAGES = 10

  sig { void }
  def show
    return render_404 unless CustomProperties::Public.enterprise_properties_enabled?(this_business)

    definitions_manager = CustomProperties::Public.definitions_manager(this_business)

    property_name = params[:property_name]

    duplicate_business_property_name = definitions_manager.get_definitions.find { |d| d.property_name.downcase == property_name.downcase }
    if duplicate_business_property_name
      return render json: business_level_name_exists_payload
    end

    all_existing_properties_in_orgs = definitions_manager.child_orgs_definitions_by_name(params[:property_name])
    if all_existing_properties_in_orgs.any?
      return render json: org_usages_exists_payload(property_name, all_existing_properties_in_orgs)
    end

    render json: valid_payload
  end

  private

  sig { returns(NameCheckPayload) }
  def business_level_name_exists_payload
    {
      status: "already_exists",
      orgConflicts: nil
    }
  end

  sig { returns(NameCheckPayload) }
  def valid_payload
    {
      status: "valid",
      orgConflicts: nil
    }
  end

  sig { params(property_name: String, all_existing_properties_in_orgs: T::Array[CustomPropertyDefinition]).returns(NameCheckPayload) }
  def org_usages_exists_payload(property_name, all_existing_properties_in_orgs)
    truncated_orgs_using_property = all_existing_properties_in_orgs.take(MAX_DISPLAYED_USAGES).index_by(&:source_id)
    orgs_with_property_name = Organization.find(truncated_orgs_using_property.keys)

    orgs_with_property_name_payload = orgs_with_property_name.map do |org|
      property = truncated_orgs_using_property[org.id]
      {
        name: org.display_login,
        avatarUrl: org.primary_avatar_url,
        propertyType: property.value_type
      }
    end

    {
      status: "exists_in_business_orgs",
      orgConflicts: {
        usages: orgs_with_property_name_payload,
        totalUsageCount: all_existing_properties_in_orgs.count
      }
    }
  end

  NameCheckPayload = T.type_alias do
    {
      status: String,
      orgConflicts: T.nilable({
        usages: T::Array[OrgDefinitionPayload],
        totalUsageCount: Integer
      })
    }
  end

  OrgDefinitionPayload = T.type_alias do
    {
      name: String,
      avatarUrl: String,
      propertyType: String
    }
  end
end
