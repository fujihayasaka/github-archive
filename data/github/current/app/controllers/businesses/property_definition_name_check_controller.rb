# typed: strict
# frozen_string_literal: true

class Businesses::PropertyDefinitionNameCheckController < Businesses::BusinessController
  include Orgs::CustomPropertiesHelper

  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
  only: [:show]

  sig { void }
  def show
    property_name = params[:property_name]

    duplicate_business_property_name = Repositories.domain.custom_properties.get_definition(this_business, property_name)

    if duplicate_business_property_name
      return render json: business_level_name_exists_payload
    end

    all_existing_properties_in_orgs = Repositories.domain.custom_properties.child_orgs_definitions_by_name(this_business, property_name)

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

  sig { params(property_name: String, all_existing_properties_in_orgs: T::Array[CustomProperties::IPropertyDefinition]).returns(NameCheckPayload) }
  def org_usages_exists_payload(property_name, all_existing_properties_in_orgs)
    {
      status: "exists_in_business_orgs",
      orgConflicts: org_conflicts_payload(property_name, all_existing_properties_in_orgs)
    }
  end

  NameCheckPayload = T.type_alias do
    {
      status: String,
      orgConflicts: T.nilable(OrgConflictsPayload)
    }
  end
end
