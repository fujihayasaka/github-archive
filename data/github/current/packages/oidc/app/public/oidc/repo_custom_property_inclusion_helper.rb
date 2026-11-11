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
      inclusion = case source
      when Organization
        OIDCCustomPropertyInclusion.create_repo_property_inclusion_for_organization!(source, property_name)
      when Business
        OIDCCustomPropertyInclusion.create_repo_property_inclusion_for_enterprise!(source, property_name)
      end

      if usage_tracking_enabled?(source)
        begin
          Repositories.domain.custom_properties.register_property_usage(property_name:, property_source: source, resource: inclusion)
        rescue StandardError => e
          GitHub.logger.error("Failed to register custom property usage for OIDC inclusion #{inclusion.id}: #{e.message}", e)
        end
      end

      instrument_inclusion_event(:created, source, property_name)

      inclusion
    end

    # Delete repository property inclusions for a source.
    sig { params(source: T.any(Organization, Business), property_names: T::Array[String]).returns(OIDCCustomPropertyInclusion::DeletionResult) }
    def delete_repo_property_inclusions_for_source!(source, property_names)
      usage_tracking_enabled = usage_tracking_enabled?(source)

      result = case source
      when Organization
        OIDCCustomPropertyInclusion.delete_repo_property_inclusion_for_organization!(source, property_names, return_deleted_inclusions: usage_tracking_enabled)
      when Business
        OIDCCustomPropertyInclusion.delete_repo_property_inclusion_for_enterprise!(source, property_names, return_deleted_inclusions: usage_tracking_enabled)
      end

      if usage_tracking_enabled
        begin
          deleted_inclusions = result.deleted_inclusions || []
          if deleted_inclusions.present?
            usages = deleted_inclusions.to_h { |inclusion| [inclusion, []] }
            Repositories.domain.custom_properties.resolve_property_usages(property_source: source, usages:)
          end
        rescue StandardError => e
          log_message_on_bulk_usage_registration_failure(source, result.deleted_inclusions || [], e)
        end
      end

      if result.deleted_inclusions.present?
        T.must(result.deleted_inclusions).each do |inclusion|
          instrument_inclusion_event(:deleted, source, inclusion.custom_property_name)
        end
      elsif result.deleted_count > 0
        # If usage tracking is disabled, we won't have the deleted inclusions to fire events for, but we can still fire a generic event for the deletion action.
        property_names.each do |property_name|
          instrument_inclusion_event(:deleted, source, property_name)
        end
      end

      result
    end

    # Atomically replaces the set of included repository properties for a source.
    # Validates the new property names, performs deletions and additions inside a single
    # transaction (skipping per-record usage registration to avoid cross-cluster nested
    # transactions), and then after the transaction:
    # - Fires appropriate instrumentation events.
    # - Resolves usage tracking in a single call after the transaction, and
    sig { params(source: T.any(Organization, Business), new_property_names: T::Array[String]).void }
    def batch_update_repo_property_inclusions!(source, new_property_names)
      current_inclusions = list_effective_repo_property_inclusions_for_source(source)
      current_included_property_names = current_inclusions.pluck(:custom_property_name).to_set

      unique_property_names = new_property_names.to_set
      properties_to_add = unique_property_names - current_included_property_names
      properties_to_remove = current_included_property_names - unique_property_names

      net_change = properties_to_add.size - properties_to_remove.size
      validate_repo_inclusion_limit_not_exceeded!(source, net_change) if net_change > 0

      deletion_result = T.let(nil, T.nilable(OIDCCustomPropertyInclusion::DeletionResult))
      added_inclusions = T.let({}, T::Hash[OIDCCustomPropertyInclusion, T::Array[String]])

      ApplicationRecord::Domain::OidcSetting.transaction do
        unless properties_to_remove.empty?
          deletion_result = case source
          when Organization
            OIDCCustomPropertyInclusion.delete_repo_property_inclusion_for_organization!(source, properties_to_remove.to_a, return_deleted_inclusions: usage_tracking_enabled?(source))
          when Business
            OIDCCustomPropertyInclusion.delete_repo_property_inclusion_for_enterprise!(source, properties_to_remove.to_a, return_deleted_inclusions: usage_tracking_enabled?(source))
          end
        end

        properties_to_add.each do |property_name|
          validate_repo_property_definition_exists!(source, property_name)
          inclusion = case source
          when Organization
            OIDCCustomPropertyInclusion.create_repo_property_inclusion_for_organization!(source, property_name)
          when Business
            OIDCCustomPropertyInclusion.create_repo_property_inclusion_for_enterprise!(source, property_name)
          end
          added_inclusions[inclusion] = [property_name]
        end
      end

      # Fire instrumentation outside the transaction
      if deletion_result && deletion_result.deleted_count > 0
        deleted_property_names = if deletion_result.deleted_inclusions.present?
          T.must(deletion_result.deleted_inclusions).map(&:custom_property_name)
        else
          properties_to_remove.to_a
        end
        deleted_property_names.each do |property_name|
          instrument_inclusion_event(:deleted, source, property_name)
        end
      end
      added_inclusions.values.flatten.each do |property_name|
        instrument_inclusion_event(:created, source, property_name)
      end

      # Resolve usage tracking in a single call outside the transaction to avoid
      # cross-cluster nested transactions.
      if usage_tracking_enabled?(source)
        usages_to_resolve = added_inclusions.dup
        deletions_present = deletion_result && deletion_result.deleted_inclusions&.present?
        if deletions_present
          usages_to_resolve.merge!(T.must(deletion_result.deleted_inclusions).to_h { |inclusion| [inclusion, []] })
        end

        if usages_to_resolve.present?
          begin
            Repositories.domain.custom_properties.resolve_property_usages(property_source: source, usages: usages_to_resolve)
          rescue StandardError => e
            log_message_on_bulk_usage_registration_failure(source, usages_to_resolve.keys, e)
          end
        end
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

    private

    sig { params(source: T.any(Organization, Business)).returns(T::Boolean) }
    def usage_tracking_enabled?(source)
      if source.is_a?(Organization)
        FeatureFlag.vexi.enabled?(:track_oidc_custom_property_inclusion_usages, source, source.business, default: false)
      else
        FeatureFlag.vexi.enabled?(:track_oidc_custom_property_inclusion_usages, source, default: false)
      end
    end

    sig { params(source: T.any(Organization, Business), input_inclusions: T::Array[OIDCCustomPropertyInclusion], error: StandardError).void }
    def log_message_on_bulk_usage_registration_failure(source, input_inclusions, error)
      GitHub.logger.error("Failed to resolve custom property usages on #{source.class.name} with ID #{source.id} for OIDC inclusions: #{input_inclusions.map(&:id).inspect}", error.message)
    end
  end
end
