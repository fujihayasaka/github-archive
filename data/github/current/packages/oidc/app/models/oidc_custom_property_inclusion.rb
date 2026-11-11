# typed: true
# frozen_string_literal: true

# OIDCCustomPropertyInclusion model
# This model extends ApplicationRecord::Domain::OidcSetting (not ::Oidc) because
# the oidc_custom_property_inclusions table is in the ActionsEnvironments database cluster,
# not the Collab cluster like other OIDC tables.
class OIDCCustomPropertyInclusion < ApplicationRecord::Domain::OidcSetting
  include CustomPropertiesCore::Usages::IPropertyResource

  # Result returned from deletion operations.
  # deleted_count: total number of records deleted
  # deleted_inclusions: array of deleted records when FF is enabled, nil otherwise
  class DeletionResult < T::Struct
    prop :deleted_count, Integer
    prop :deleted_inclusions, T.nilable(T::Array[OIDCCustomPropertyInclusion])
  end

  # This represents the maximum number of OIDC custom property inclusions
  # This is the total Org + Enterprise limit
  FETCH_LIMIT = 200

  enum :source_type, {
    organization: 0,
    enterprise: 1
  }

  enum :property_type, {
    repository_property: 0,
    organization_property: 1
  }

  validates :source_id, presence: true
  validates :source_type, presence: true
  validates :property_type, presence: true
  validates :custom_property_name, presence: true
  validates :custom_property_name, uniqueness: { scope: [:source_id, :source_type, :property_type] }
  validate :organization_property_inclusion_only_at_enterprise_level

  sig { override.returns(T.nilable(Integer)) }
  def properties_resource_id
    id
  end

  sig { override.returns(String) }
  def properties_resource_type
    self.class.name.to_s
  end

  # Get all OIDC custom property inclusions for an organization
  sig { params(org_id: Integer).returns(T.untyped) }
  def self.repo_property_inclusions_for_organization(org_id)
    where(source_id: org_id, source_type: :organization, property_type: :repository_property)
  end

  # Get all OIDC custom property inclusions for an enterprise
  sig { params(enterprise_id: Integer).returns(T.untyped) }
  def self.repo_property_inclusions_for_enterprise(enterprise_id)
    where(source_id: enterprise_id, source_type: :enterprise, property_type: :repository_property)
  end

  # Get all OIDC custom property inclusions for an organization and its enterprise
  sig { params(org_id: Integer, enterprise_id: T.nilable(Integer)).returns(T.untyped) }
  def self.repo_property_inclusions_for_organization_and_enterprise(org_id, enterprise_id)
    if enterprise_id
      repo_property_inclusions_for_organization(org_id).or(repo_property_inclusions_for_enterprise(enterprise_id))
    else
      repo_property_inclusions_for_organization(org_id)
    end
  end

  # Create a new OIDC repository property inclusion for an organization
  sig { params(org: Organization, property_name: String).returns(OIDCCustomPropertyInclusion) }
  def self.create_repo_property_inclusion_for_organization!(org, property_name)
    create!(
      source_id: org.id,
      source_type: :organization,
      property_type: :repository_property,
      custom_property_name: property_name
    )
  end

  # Create a new OIDC repository property inclusion for an enterprise
  sig { params(enterprise: Business, property_name: String).returns(OIDCCustomPropertyInclusion) }
  def self.create_repo_property_inclusion_for_enterprise!(enterprise, property_name)
    create!(
      source_id: enterprise.id,
      source_type: :enterprise,
      property_type: :repository_property,
      custom_property_name: property_name
    )
  end

  # Delete OIDC repository property inclusion for an organization
  # Returns a DeletionResult with deleted_count and optional deleted_inclusions.
  sig { params(org: Organization, property_names: T.any(String, T::Array[String]), return_deleted_inclusions: T::Boolean).returns(DeletionResult) }
  def self.delete_repo_property_inclusion_for_organization!(org, property_names, return_deleted_inclusions: false)
    property_names = Array.wrap(property_names)

    if return_deleted_inclusions
      deleted_inclusions = where(
        source_id: org.id,
        source_type: :organization,
        property_type: :repository_property,
        custom_property_name: property_names,
      ).destroy_all

      DeletionResult.new(deleted_count: deleted_inclusions.size, deleted_inclusions: deleted_inclusions)
    else
      count = where(
        source_id: org.id,
        source_type: :organization,
        property_type: :repository_property,
        custom_property_name: property_names
      ).delete_all
      DeletionResult.new(deleted_count: count, deleted_inclusions: nil)
    end
  end

  # Delete OIDC repository property inclusion for an enterprise
  # Returns a DeletionResult with deleted_count and optional deleted_inclusions.
  sig { params(enterprise: Business, property_names: T.any(String, T::Array[String]), return_deleted_inclusions: T::Boolean).returns(DeletionResult) }
  def self.delete_repo_property_inclusion_for_enterprise!(enterprise, property_names, return_deleted_inclusions: false)
    property_names = Array.wrap(property_names)

    if return_deleted_inclusions
      deleted_inclusions = where(
        source_id: enterprise.id,
        source_type: :enterprise,
        property_type: :repository_property,
        custom_property_name: property_names
      ).destroy_all

      DeletionResult.new(deleted_count: deleted_inclusions.size, deleted_inclusions: deleted_inclusions)
    else
      count = where(
        source_id: enterprise.id,
        source_type: :enterprise,
        property_type: :repository_property,
        custom_property_name: property_names
      ).delete_all
      DeletionResult.new(deleted_count: count, deleted_inclusions: nil)
    end
  end

  # Get the effective custom properties for a repository that have been opted-in for OIDC token inclusion
  sig do
    params(
      org: T.nilable(Organization),
      enterprise: T.nilable(Business),
      effective_repo_properties: T::Hash[String, CustomPropertiesCore::PropertyValue]
    ).returns(T::Hash[String, T.nilable(CustomPropertiesCore::PropertyValue)])
  end
  def self.included_repo_properties(org, enterprise, effective_repo_properties)
    return {} if org.nil?

    oidc_inclusions = repo_property_inclusions_for_organization_and_enterprise(org.id, enterprise&.id)
    oidc_prop_names = oidc_inclusions.limit(FETCH_LIMIT).pluck(:custom_property_name).to_set

    effective_repo_properties.select do |prop_name, prop_value|
      prop_value.present? && oidc_prop_names.include?(prop_name)
    end
  end

  private

  def organization_property_inclusion_only_at_enterprise_level
    if organization_property? && organization?
      errors.add(:base, "Organization properties can only be defined at the enterprise level")
    end
  end
end
