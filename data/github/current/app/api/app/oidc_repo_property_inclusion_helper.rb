# typed: true
# frozen_string_literal: true

# Helper module for OIDC custom property inclusion API operations.
# This module provides validation and CRUD operations for managing which
# repository custom properties are included in Actions OIDC tokens.
#
# Designed to be included in API controllers (org and enterprise level).
module Api::App::OIDCRepoPropertyInclusionHelper
  extend T::Helpers
  include Api::App::HelpersDependency
  include OIDC::RepoCustomPropertyInclusionHelper

  requires_ancestor { Api::App }

  # List all repository property inclusions for an organization.
  # Results are capped at OIDC::RepoCustomPropertyInclusionHelper::DEFAULT_LIMIT.
  sig { params(organization: Organization).returns(T::Array[OIDCCustomPropertyInclusion]) }
  def list_repo_property_inclusions_for_organization(organization)
    list_repo_property_inclusions_for_source(organization)
  end

  # List all repository property inclusions for an enterprise.
  # Results are capped at OIDC::RepoCustomPropertyInclusionHelper::DEFAULT_LIMIT.
  sig { params(enterprise: Business).returns(T::Array[OIDCCustomPropertyInclusion]) }
  def list_repo_property_inclusions_for_enterprise(enterprise)
    list_repo_property_inclusions_for_source(enterprise)
  end

  # Create a repository property inclusion for an organization.
  # Validates that the custom property definition exists before creating.
  # Raises LimitExceededError if the maximum number of inclusions has been reached.
  sig { params(organization: Organization, property_name: String).returns(OIDCCustomPropertyInclusion) }
  def create_repo_property_inclusion_for_organization!(organization, property_name)
    validate_repo_property_definition_exists!(organization, property_name)
    validate_repo_inclusion_limit_not_exceeded!(organization)

    create_repo_property_inclusion_for_source!(organization, property_name)
  end

  # Create a repository property inclusion for an enterprise.
  # Validates that the custom property definition exists before creating.
  # Raises LimitExceededError if the maximum number of inclusions has been reached.
  sig { params(enterprise: Business, property_name: String).returns(OIDCCustomPropertyInclusion) }
  def create_repo_property_inclusion_for_enterprise!(enterprise, property_name)
    validate_repo_property_definition_exists!(enterprise, property_name)
    validate_repo_inclusion_limit_not_exceeded!(enterprise)

    create_repo_property_inclusion_for_source!(enterprise, property_name)
  end

  # Delete a repository property inclusion for an organization.
  # Returns the number of deleted records (0 if not found).
  sig { params(organization: Organization, property_name: String).returns(Integer) }
  def delete_repo_property_inclusion_for_organization(organization, property_name)
    result = delete_repo_property_inclusions_for_source!(organization, [property_name])
    result.deleted_count
  end

  # Delete a repository property inclusion for an enterprise.
  # Returns the number of deleted records (0 if not found).
  sig { params(enterprise: Business, property_name: String).returns(Integer) }
  def delete_repo_property_inclusion_for_enterprise(enterprise, property_name)
    result = delete_repo_property_inclusions_for_source!(enterprise, [property_name])
    result.deleted_count
  end
end
