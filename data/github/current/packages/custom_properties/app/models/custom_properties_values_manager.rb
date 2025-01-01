# typed: strict
# frozen_string_literal: true

class CustomPropertiesValuesManager
  include CustomProperties
  include CustomPropertiesCore
  include CustomPropertiesCore::Errors
  include CustomPropertiesCore::IValuesManager

  # Public: Initializes a new instance to handle the properties for an org
  #
  # definitions_manager - A definitions object that can be used to manage property definitions
  sig { params(definitions_manager: CustomPropertiesDefinitionsManager).void }
  def initialize(definitions_manager)
    @source = T.let(definitions_manager.source, IPropertySource)
    @config = T.let(definitions_manager.config, ICustomPropertiesConfig)
    @definitions_manager = definitions_manager
  end

  # Public: Validate values and definitions against the schema for the collection's org
  #
  # properties - A hash of properties to validate
  #
  # Returns an array of errors. Empty array means that properties are valid.
  sig { override.params(properties: T::Hash[T.any(String, Symbol), PropertyValue]).returns(T::Array[SchemaValidationError]) }
  def validate_properties(properties)
    properties = T.let(properties.stringify_keys, T::Hash[String, PropertyValue])
    CustomPropertiesValidator.validate_properties(@definitions_manager.get_definitions, properties)
  end

  sig do
    override.params(
      targets: T::Array[IPropertyTarget],
      properties: T::Hash[String, PropertyValue],
    ).void.checked(:always).on_failure(:raise)
  end
  def set_properties_for(targets, properties)
    target_class_name = T.let(T.unsafe(@config.value_class).target_class_name, String)
    malformed_entity_types = T.let(
      targets.select { |entity| entity.class.name != target_class_name }
      .map { |entity| entity.class.name }
      .uniq, T::Array[String]
    )
    if malformed_entity_types.any?
      raise ArgumentError,
        "Invalid entity: Entities with type #{malformed_entity_types.join(", ")} don't match custom property value target type #{target_class_name}."
    end

    assert_no_validation_errors!(properties)

    definition_ids_hash = properties.to_h { |name, _| [T.must(@definitions_manager.get_definition(name)).id, name] }

    @config.value_class.transaction do
      entities_values_hash = T.unsafe(@config.value_class).for_target_ids(targets.map(&:properties_target_id)).for_definition_ids(definition_ids_hash.keys).group_by(&:target_id)

      targets.each do |target|
        name_to_rows_group = (entities_values_hash[target.properties_target_id] || []).group_by { |row| T.must(definition_ids_hash[row.definition_id]) }
        delete_properties = T.let([], T::Array[ValueBase])
        create_properties = T.let([], T::Array[[String, String]])

        properties.each_pair do |name, values|
          values = Array(values).compact_blank
          rows = name_to_rows_group.fetch(name, [])
          stored_values = name_to_rows_group.fetch(name, [])
          values_to_create = values - rows.map(&:value)
          rows_to_delete = rows.filter { |row| !values.include?(row.value) }

          delete_properties += rows_to_delete
          create_properties += values_to_create.map { |value| [name, value] }
        end

        # Before update it, we need calculate the old values for the telemetry
        old_properties = properties.keys.index_with do |name|
          definition = T.must(@definitions_manager.get_definition(name))
          values = name_to_rows_group.fetch(name, []).map(&:value).sort

          next nil if values.empty?

          if definition.multi_select_value_type?
            values
          else
            values.first
          end
        end

        delete_properties.each { |row| row.destroy! }
        create_properties.each do |name, value|
          @config.value_class.create!(
            target_id: target.properties_target_id,
            definition: @definitions_manager.get_definition(name),
            value: value
          )
        end

        if properties.any?
          event_payload = {
            new_values: properties.transform_values { |value| value.blank? ? nil : value },
            old_values: old_properties,
          }.merge(T.unsafe(@config.value_class).get_event_payload_extension(target))

          event_name = "#{T.unsafe(@config.value_class).get_event_prefix}.update_custom_property_values"

          GitHub.instrument event_name, event_payload
        end
      end
    end
  end

  # Public: Case insensitive search for property values that match a search term for a given definition.
  #
  # property_name  - The name of the property definition to search values for
  # search_term    - The search term to match against property values
  # limit          - Optional maximum number of results to return
  #
  # Returns an array of unique matching property values sorted alphabetically.
  sig { override.params(property_name: String, search_term: String, limit: T.nilable(Integer)).returns(T::Array[String]) }
  def search_property_values(property_name, search_term, limit: nil)
    definition = @definitions_manager.get_definition(property_name)
    raise ArgumentError, "Invalid entity: property with name #{property_name} does not exist in #{@source}'s schema" unless definition

    T.unsafe(@config.value_class).for_definition(definition)
      .with_property_value_like(search_term)
      .order(value: :asc)
      .distinct
      .limit(limit)
      .pluck(:value)
  end

  private

  sig { params(properties: T::Hash[String, T.untyped]).returns(T.nilable(PropertyValidationError)) }
  def assert_no_validation_errors!(properties)
    errors = validate_properties(properties)

    raise PropertyValidationError.new(errors) if errors.any?
  end
end
