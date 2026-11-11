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
  include Instrumentation::Model
  include OIDC::RepoCustomPropertyInclusionHelper

  requires_ancestor { Api::App }

  # Add a reasonable limit. We don't want an excessive number of claims in an OIDC token.
  DEFAULT_LIMIT = 100

  # List all repository property inclusions for an organization.
  # Results are capped at DEFAULT_LIMIT.
  sig { params(organization: Organization).returns(T::Array[OIDCCustomPropertyInclusion]) }
  def list_repo_property_inclusions_for_organization(organization)
    OIDCCustomPropertyInclusion
      .repo_property_inclusions_for_organization(organization.id)
      .limit(DEFAULT_LIMIT)
      .to_a
  end

  # List all repository property inclusions for an enterprise.
  # Results are capped at DEFAULT_LIMIT.
  sig { params(enterprise: Business).returns(T::Array[OIDCCustomPropertyInclusion]) }
  def list_repo_property_inclusions_for_enterprise(enterprise)
    OIDCCustomPropertyInclusion
      .repo_property_inclusions_for_enterprise(enterprise.id)
      .limit(DEFAULT_LIMIT)
      .to_a
  end

  # Create a repository property inclusion for an organization.
  # Validates that the custom property definition exists before creating.
  # Raises LimitExceededError if the maximum number of inclusions has been reached.
  sig { params(organization: Organization, property_name: String).returns(OIDCCustomPropertyInclusion) }
  def create_repo_property_inclusion_for_organization!(organization, property_name)
    validate_repo_property_definition_exists!(organization, property_name)
    validate_inclusion_limit_not_exceeded!(organization)

    inclusion = OIDCCustomPropertyInclusion.create_repo_property_inclusion_for_organization!(organization.id, property_name)
    instrument_inclusion_event(:created, organization, property_name)
    inclusion
  end

  # Create a repository property inclusion for an enterprise.
  # Validates that the custom property definition exists before creating.
  # Raises LimitExceededError if the maximum number of inclusions has been reached.
  sig { params(enterprise: Business, property_name: String).returns(OIDCCustomPropertyInclusion) }
  def create_repo_property_inclusion_for_enterprise!(enterprise, property_name)
    validate_repo_property_definition_exists!(enterprise, property_name)
    validate_inclusion_limit_not_exceeded!(enterprise)

    inclusion = OIDCCustomPropertyInclusion.create_repo_property_inclusion_for_enterprise!(enterprise.id, property_name)
    instrument_inclusion_event(:created, enterprise, property_name)
    inclusion
  end

  # Delete a repository property inclusion for an organization.
  # Returns the number of deleted records (0 if not found).
  sig { params(organization: Organization, property_name: String).returns(Integer) }
  def delete_repo_property_inclusion_for_organization(organization, property_name)
    deleted_count = OIDCCustomPropertyInclusion.delete_repo_property_inclusion_for_organization!(organization.id, property_name)
    instrument_inclusion_event(:deleted, organization, property_name) if deleted_count > 0
    deleted_count
  end

  # Delete a repository property inclusion for an enterprise.
  # Returns the number of deleted records (0 if not found).
  sig { params(enterprise: Business, property_name: String).returns(Integer) }
  def delete_repo_property_inclusion_for_enterprise(enterprise, property_name)
    deleted_count = OIDCCustomPropertyInclusion.delete_repo_property_inclusion_for_enterprise!(enterprise.id, property_name)
    instrument_inclusion_event(:deleted, enterprise, property_name) if deleted_count > 0
    deleted_count
  end

  private

  # Instruments an OIDC custom property inclusion event.
  # Builds the correct event name (e.g., org.oidc_custom_property_inclusion_created)
  # based on whether the source is an Organization or Business.
  sig { params(action: Symbol, source: T.any(Organization, Business), property_name: String).void }
  def instrument_inclusion_event(action, source, property_name)
    is_enterprise = source.is_a?(Business)
    prefix = is_enterprise ? :enterprise : :org
    owner_hash = is_enterprise ? { business: source } : { org: source }

    instrument :"oidc_custom_property_inclusion_#{action}", owner_hash.merge(
      prefix: prefix,
      property_name: property_name,
      property_type: "repository"
    )
  end

  # Error raised when a custom property definition does not exist
  class PropertyNotFoundError < StandardError
    attr_reader :property_name

    def initialize(property_name)
      @property_name = property_name
      super("Custom property '#{property_name}' does not exist")
    end
  end

  # Error raised when the maximum number of property inclusions has been reached
  class LimitExceededError < StandardError
    attr_reader :limit

    def initialize(limit)
      @limit = limit
      super("Maximum number of property inclusions (#{limit}) has been reached")
    end
  end

  # Validates that the custom property definition exists for the given source.
  # Raises PropertyNotFoundError if not found.
  sig { params(source: T.any(Organization, Business), property_name: String).void }
  def validate_repo_property_definition_exists!(source, property_name)
    definition = Repositories.domain.custom_properties.get_definition(source, property_name)
    if definition.nil?
      raise PropertyNotFoundError.new(property_name)
    end
  end

  # Validates that the source has not exceeded the maximum number of property inclusions.
  # Raises LimitExceededError if the limit has been reached.
  sig { params(source: T.any(Organization, Business)).void }
  def validate_inclusion_limit_not_exceeded!(source)
    current_count = case source
    when Organization
      OIDCCustomPropertyInclusion.repo_property_inclusions_for_organization(source.id).limit(DEFAULT_LIMIT).count
    when Business
      OIDCCustomPropertyInclusion.repo_property_inclusions_for_enterprise(source.id).limit(DEFAULT_LIMIT).count
    end

    if current_count >= DEFAULT_LIMIT
      raise LimitExceededError.new(DEFAULT_LIMIT)
    end
  end
end
