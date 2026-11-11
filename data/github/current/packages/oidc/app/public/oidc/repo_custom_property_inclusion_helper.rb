# typed: strict
# frozen_string_literal: true

module OIDC
  module RepoCustomPropertyInclusionHelper
    extend T::Helpers

    include Kernel

    # Add a reasonable limit. We don't want an excessive number of claims in an OIDC token.
    DEFAULT_LIMIT = 100

    # List all repository property inclusions for a source.
    # Results are capped at DEFAULT_LIMIT.
    sig { params(source: T.any(Organization, Business)).returns(T::Array[OIDCCustomPropertyInclusion]) }
    def list_repo_property_inclusions_for_source(source)
      case source
      when Organization
        OIDCCustomPropertyInclusion.repo_property_inclusions_for_organization(source.id).limit(DEFAULT_LIMIT).to_a
      when Business
        OIDCCustomPropertyInclusion.repo_property_inclusions_for_enterprise(source.id).limit(DEFAULT_LIMIT).to_a
      end
    end

    # Create a repository property inclusion for a source.
    sig { params(source: T.any(Organization, Business), property_name: String).returns(OIDCCustomPropertyInclusion) }
    def create_repo_property_inclusion_for_source!(source, property_name)
      case source
      when Organization
        OIDCCustomPropertyInclusion.create_repo_property_inclusion_for_organization!(source.id, property_name)
      when Business
        OIDCCustomPropertyInclusion.create_repo_property_inclusion_for_enterprise!(source.id, property_name)
      end
    end

    # Delete repository property inclusions for a source.
    sig { params(source: T.any(Organization, Business), property_names: T::Array[String]).returns(Integer) }
    def delete_repo_property_inclusions_for_source!(source, property_names)
      case source
      when Organization
        OIDCCustomPropertyInclusion.delete_repo_property_inclusion_for_organization!(source.id, property_names)
      when Business
        OIDCCustomPropertyInclusion.delete_repo_property_inclusion_for_enterprise!(source.id, property_names)
      end
    end

    # Error raised when a custom property definition does not exist
    class PropertyNotFoundError < StandardError
      sig { returns(String) }
      attr_reader :property_name

      sig { params(property_name: String).void }
      def initialize(property_name)
        @property_name = property_name
        super("Custom property '#{property_name}' does not exist")
      end
    end

    # Error raised when the maximum number of property inclusions has been reached
    class LimitExceededError < StandardError
      sig { returns(Integer) }
      attr_reader :limit

      sig { params(limit: Integer).void }
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
      raise PropertyNotFoundError.new(property_name) if definition.nil?
    end

    # List all effective repository property inclusions for a source.
    # For organizations, returns both enterprise and org level inclusions,
    # with enterprise inclusions taking precedence when a property name exists at both levels.
    # For enterprises, returns enterprise-level inclusions only.
    sig { params(source: T.any(Organization, Business)).returns(T::Array[OIDCCustomPropertyInclusion]) }
    def list_effective_repo_property_inclusions_for_source(source)
      case source
      when Organization
        business = source.business
        if business
          org_inclusions = OIDCCustomPropertyInclusion.repo_property_inclusions_for_organization(source.id)
          enterprise_inclusions = OIDCCustomPropertyInclusion.repo_property_inclusions_for_enterprise(business.id)

          enterprise_inclusions.or(
            org_inclusions.where.not(custom_property_name: enterprise_inclusions.select(:custom_property_name))
          ).limit(OIDCCustomPropertyInclusion::FETCH_LIMIT).to_a
        else
          OIDCCustomPropertyInclusion.repo_property_inclusions_for_organization(source.id).limit(DEFAULT_LIMIT).to_a
        end
      when Business
        OIDCCustomPropertyInclusion.repo_property_inclusions_for_enterprise(source.id).limit(DEFAULT_LIMIT).to_a
      end
    end

    sig { params(source: T.any(Organization, Business), net_change: Integer).void }
    def validate_repo_inclusion_limit_not_exceeded!(source, net_change = 1)
      current_count = case source
      when Organization
        OIDCCustomPropertyInclusion.repo_property_inclusions_for_organization(source.id).limit(DEFAULT_LIMIT).count
      when Business
        OIDCCustomPropertyInclusion.repo_property_inclusions_for_enterprise(source.id).limit(DEFAULT_LIMIT).count
      end

      raise LimitExceededError.new(DEFAULT_LIMIT) if current_count + net_change > DEFAULT_LIMIT
    end

    # Instruments an OIDC custom property inclusion event.
    # Builds the correct event name (e.g., org.oidc_custom_property_inclusion_created)
    # based on whether the source is an Organization or Business.
    sig { params(action: Symbol, source: T.any(Organization, Business), property_name: String).void }
    def instrument_inclusion_event(action, source, property_name)
      is_enterprise = source.is_a?(Business)
      prefix = is_enterprise ? :enterprise : :org
      owner_hash = is_enterprise ? { business: source } : { org: source }

      source.instrument :"oidc_custom_property_inclusion_#{action}", owner_hash.merge(
        prefix: prefix,
        property_name: property_name,
        property_type: "repository"
      )
    end
  end
end
