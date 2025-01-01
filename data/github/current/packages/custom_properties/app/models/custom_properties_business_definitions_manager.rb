# typed: strict
# frozen_string_literal: true

class CustomPropertiesBusinessDefinitionsManager < CustomPropertiesDefinitionsManager
  include CustomProperties
  include CustomProperties::Errors
  include GitHub::Memoizer

  # Public: Initializes a new instance to handle the properties for an org
  #
  # source - The business to handle properties for
  sig { params(source: ::Business).void.checked(:always).on_failure(:raise) }
  def initialize(source)
    unless Public.enterprise_properties_enabled?(source)
      raise ArgumentError.new "Unsupported source type: '#{source.class.name}'"
    end

    super(source)
    @source = source
  end

  # Public: Promote a property definition from an organization to the enterprise level.
  # Promotion requires using business level definitions manager.
  # Property can be promoted only if there are no other properties with the same name in the enterprise orgs.
  #
  # definition - Org level property definition to promote
  sig { params(definition: IPropertyDefinition).void }
  def promote_definition(definition)
    raise ArgumentError.new "Enterprise property cannot be promoted" if definition.business_source_type?
    raise ArgumentError.new "Property source must be a member of #{@source.name}" unless defined_on_current_business_orgs?(definition)
    if find_definition_by_name(@definitions_collection.resolved_definitions, definition.property_name).present?
      raise ArgumentError.new "Property already exists in the enterprise schema"
    end
    raise_if_too_many_definitions!(@definitions_collection.own_definitions_count + 1)

    duplicate_definitions_by_definition_id = child_orgs_definitions_by_name(definition.property_name).index_by(&:id)

    promoted_definition = duplicate_definitions_by_definition_id.delete(definition.id)
    duplicate_definitions = duplicate_definitions_by_definition_id.values

    raise ArgumentError.new "Property not found" if promoted_definition.nil?
    if duplicate_definitions.any?
      error = "Cannot promote property. #{duplicate_business_definitions_error_message(duplicate_definitions, definition.property_name)}"
      raise ArgumentError.new error
    end

    promoted_definition.update!(source_id: @source.id, source_type: "business")

    @definitions_collection.remove_cached_definitions
    reindex_org_repos
  end

  # Case insensitive search for definitions with similar name in child orgs
  # Returns a list of definitions.
  sig { params(property_name: String).returns(T::Array[CustomPropertyDefinition]) }
  def child_orgs_definitions_by_name(property_name)
    CustomPropertyDefinition
      .where(source_id: business_organization_ids, source_type: "org")
      .where("property_name LIKE ?", property_name.downcase)
      .to_a
  end

  private

  sig { params(definition: IPropertyDefinition).returns(T::Boolean) }
  def defined_on_current_business_orgs?(definition)
    business_organization_ids.include?(definition.source_id)
  end

  sig { returns(T::Array[Integer]) }
  memoize def business_organization_ids
    @source.organizations.pluck(:id)
  end

  sig { params(property_name: String).void }
  def raise_if_duplicate_property_name!(property_name)
    super(property_name)

    duplicate_definitions = child_orgs_definitions_by_name(property_name)

    if duplicate_definitions.any?
      raise ArgumentError.new "Failed to save custom property. #{duplicate_business_definitions_error_message(duplicate_definitions, property_name)}"
    end
  end

  sig { params(duplicate_definitions: T::Array[CustomPropertyDefinition], property_name: String).returns(String) }
  def duplicate_business_definitions_error_message(duplicate_definitions, property_name)
    return "" if duplicate_definitions.empty?
    first_org = duplicate_definitions.first&.source
    return "" unless first_org.is_a?(Organization)

    other_orgs_count = duplicate_definitions.size - 1

    error = "Property '#{property_name}' is already defined in '#{first_org.display_login}'"
    error += " and #{other_orgs_count} other enterprise #{"organization".pluralize(other_orgs_count)}" if other_orgs_count > 0
    error += ". Property name uniqueness is case insensitive."

    error
  end
end
