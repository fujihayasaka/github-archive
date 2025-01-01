# typed: strict
# frozen_string_literal: true

class CustomPropertiesDefinitionsManager
  include CustomProperties
  include CustomPropertiesCore
  include CustomPropertiesCore::Errors
  include CustomPropertiesCore::IDefinitionsManager
  include GitHub::Memoizer

  sig { returns(PropertySource) }
  attr_reader :source

  sig { returns(ICustomPropertiesConfig) }
  attr_reader :config

  # Public: Initializes a new instance to handle the properties for an org
  #
  # source - The org or business to handle properties for
  sig { params(source: PropertySource, config: ICustomPropertiesConfig).void }
  def initialize(source, config)
    if self.instance_of?(CustomPropertiesDefinitionsManager)
      raise ArgumentError.new "Avoid using 'CustomPropertiesDefinitionsManager' unless working with 'Organization' source" unless source.is_a?(Organization)
    end

    @config = T.let(config, ICustomPropertiesConfig)
    @source = source
    @source_type = T.let(@source.is_a?(::Organization) ? "org" : "business", String)
    @definitions_collection = T.let(DefinitionsCollection.new(@source, @config), DefinitionsCollection)
  end

  # Public: Read definitions for the collection's org
  #
  # Returns sorted list of definitions
  # If both org and business definitions exist, schema is resolved.
  # Business definitions take precedence over org definitions.
  #
  # If `only_defined_by_source` is true, only definitions defined at current source are returned.
  # WARNING: `only_defined_by_source` is only meant for properties admin purposes.
  # Avoid using it for integrations with properties.
  sig { override.params(only_defined_by_source: T::Boolean).returns(T::Array[IPropertyDefinition]) }
  def get_definitions(only_defined_by_source: false)
    if only_defined_by_source
      @definitions_collection.own_definitions
    else
      @definitions_collection.resolved_definitions
    end
  end

  # Public: Get definition by property name
  #
  # Returns the definition model or nil if it does not exist
  # If both org and business definitions exist, schema is resolved.
  # Business definitions take precedence over org definitions.
  sig { override.params(property_name: String).returns(T.nilable(IPropertyDefinition)) }
  def get_definition(property_name)
    find_definition_by_name(@definitions_collection.resolved_definitions, property_name)
  end


  #  Public: Get the number of definitions owned by the current source.
  #
  # Returns the number of definitions
  sig { returns(Integer) }
  def own_definitions_count
    @definitions_collection.own_definitions_count
  end

  # Public: Add or replace the definition of a custom property for the collection's org
  #
  # property_name - Property name to define
  # value_type - Type of the property value. One of ["string", "single_select", "multi_select", "true_false"]. Defaults to "string".
  # required - Whether the property is required or not. Defaults to false.
  # default_value - Default value for the property. Defaults to nil. Must be provided if required is true.
  # description - Description of the property. Defaults to nil.
  # allowed_values - Allowed values for the property. Defaults to nil.
  # values_editable_by - Who can edit the values of the property. One of ["org_actors", "org_and_repo_actors"]. Defaults to "org_actors".
  #
  # Returns the definition model
  sig do
    override.params(
      property_name: String,
      value_type: String,
      required: T::Boolean,
      default_value: T.nilable(PropertyValue),
      description: T.nilable(String),
      allowed_values: T.nilable(T::Array[String]),
      values_editable_by: T.nilable(String),
      regex: T.nilable(String),
    ).returns(IPropertyDefinition)
  end
  def save_definition(property_name:, value_type: "string", required: false, default_value: nil, description: nil, allowed_values: nil, values_editable_by: nil, regex: nil)
    definition = find_definition_by_name(@definitions_collection.resolved_definitions, property_name)
    if definition
      raise_if_wrong_source_type!(definition)
      raise_if_value_type_changed!(definition, value_type)

      usages_checker = AllowedUsagesValueChecker.new(definition, allowed_values, @config)
      usages_checker.check!

      definition.update!(
        value_type: value_type,
        description: description,
        allowed_values: allowed_values,
        required: required,
        values_editable_by: values_editable_by,
        config: {
          default_value: default_value,
          regex: regex,
        },
      )

      usages_checker.delete_value_rows!
    else
      # Ensure we can create a new definition without passing the max number of definitions
      raise_if_too_many_definitions!(@definitions_collection.own_definitions_count + 1)
      raise_if_duplicate_property_name!(property_name)

      definition = @config.definition_class.create!(
        source: @source,
        property_name: property_name,
        value_type: value_type,
        description: description,
        allowed_values: allowed_values,
        required: required,
        values_editable_by: values_editable_by,
        config: {
          default_value: default_value,
          regex: regex,
        },
      )
    end
    @definitions_collection.remove_cached_definitions

    definition
  rescue ActiveRecord::RecordInvalid => exception
    raise InvalidDefinition.new exception.message
  rescue ActiveRecord::RecordNotUnique => exception
    raise ArgumentError.new "Failed to save custom property. Property already exists with similar name. Property name uniqueness is case insensitive."
  end

  # Public: Delete definition for the collection's org
  #
  # property_name - A property_name to remove
  #
  # Returns the deleted definition or nil if it did not exist
  sig { override.params(property_name: String).returns(T.nilable(IPropertyDefinition)) }
  def delete_definition(property_name)
    definition = find_definition_by_name(@definitions_collection.own_definitions, property_name)

    return nil unless definition
    raise_if_wrong_source_type!(definition)

    definition.destroy!

    @definitions_collection.remove_cached_definitions

    definition
  end

  # Merges org and business definitions, ensuring that business definitions take precedence over org definitions.
  # Returns a new array of definitions sorted by property name.
  sig { params(business_defs: T::Array[DefinitionBase], org_defs: T::Array[DefinitionBase]).returns(T::Array[DefinitionBase]) }
  def self.merge_definitions(business_defs, org_defs)
    biz_prop_names_set = business_defs.map { |defn| defn.property_name.downcase }.to_set
    org_defs = org_defs.filter { |defn| !biz_prop_names_set.include?(defn.property_name.downcase) }

    (org_defs + business_defs).sort_by { |defn| defn.property_name.downcase }
  end

  sig { override.params(definition: IPropertyDefinition).returns(IPropertyDefinition) }
  def promote_definition(definition)
    raise NotImplementedError, "This method is implemented by the business definitions manager"
  end

  sig { override.params(property_name: String).returns(T::Array[DefinitionBase]) }
  def child_orgs_definitions_by_name(property_name)
    raise NotImplementedError, "This method is implemented by the business definitions manager"
  end

  private

  # Case insensitive search for a definition by property name
  sig { params(definitions: T::Array[DefinitionBase], property_name: String).returns(T.nilable(DefinitionBase)) }
  def find_definition_by_name(definitions, property_name)
    definitions.find { |d| d.property_name.downcase == property_name.downcase }
  end

  sig { params(definition_number: Integer).void }
  def raise_if_too_many_definitions!(definition_number)
    limit = Public::DEFINITION_LIMIT
    if definition_number > limit
      raise DefinitionLimitReachedError, "Too many definitions. Definitions are limited to #{limit} per #{@source.is_a?(::Organization) ? "organization" : "enterprise"}."
    end
  end

  sig { params(property_name: String).void }
  def raise_if_duplicate_property_name!(property_name)
    duplicate_property_name = find_definition_by_name(@definitions_collection.resolved_definitions, property_name)&.property_name
    if duplicate_property_name.present?
      raise ArgumentError.new "Failed to save custom property. Property already exists with similar name '#{duplicate_property_name}'. Property name uniqueness is case insensitive."
    end
  end

  sig { params(definition: IPropertyDefinition).void }
  def raise_if_wrong_source_type!(definition)
    if @source_type != definition.source_type
      raise InvalidDefinition.new "Cannot change '#{definition.property_name}'. Property is defined at #{definition.source_type == "org" ? "organization" : "enterprise"} level."
    end
  end

  sig { params(definition: IPropertyDefinition, new_value_type: String).void }
  def raise_if_value_type_changed!(definition, new_value_type)
    unless definition.value_type == new_value_type
      raise InvalidDefinition.new "Unable to save '#{definition.property_name}'. Value type cannot be changed."
    end
  end

  class AllowedUsagesValueChecker
    include GitHub::Memoizer
    include CustomProperties
    include CustomPropertiesCore

    sig { params(definition: IPropertyDefinition, new_allowed_values: T.nilable(T::Array[String]), config: ICustomPropertiesConfig).void }
    def initialize(definition, new_allowed_values, config)
      @definition = definition
      @missing_allowed_values = T.let(allowed_values_to_remove(definition, new_allowed_values), T::Array[String])
      @config = config
    end

    # Public: Checks if the allowed values to be deleted are in use by any repo.
    # Usages from targets excluded by with_target_scope are not considered.
    # Raises a DefinitionDeletionAllowValueInUseError with a descriptive message.
    sig { void }
    def check!
      return if @missing_allowed_values.empty?
      return if value_rows.empty?

      target_ids = value_rows.pluck(:target_id).compact.uniq

      # We want a distinct target count for our error message, not a count of matching value rows
      target_count = if T.unsafe(@config.value_class).respond_to?(:target_scope)
        # value_rows holds all value rows including orphaned rows that match the missing allowed values
        # We need to check if any of the values are in use by active targets defined by target_scope
        target_klass = T.unsafe(@config.value_class).target_class_name.constantize
        target_scope = T.unsafe(@config.value_class).target_scope
        target_klass.where(id: target_ids).instance_exec(&target_scope).count
      else
        # If we do not need to apply a target_scope, then we can just count the unique target_ids
        target_ids.count
      end

      return if target_count.zero?

      values_with_commas = @missing_allowed_values.sort.map { |value| "'#{value}'" }.join(", ")
      allowed_values_text = "#{values_with_commas} referenced by #{target_count} #{T.unsafe(@config.value_class).target_class_name.pluralize(target_count)}"
      message = "Unable to save '#{@definition.property_name}' because you can't delete options that are in use: #{allowed_values_text}."
      raise CustomPropertiesCore::Errors::DefinitionDeletionAllowValueInUseError.new message
    end

    # Public: Deletes the value rows corresponding to the allowed values that are being deleted
    # Useful to delete orphan rows after the definition has been updated.
    # This is expected to be called only with soft-deleted repos values.
    sig { void }
    def delete_value_rows!
      return if @missing_allowed_values.empty?

      value_rows.each(&:destroy!)
    end

    private

    sig { params(definition: IPropertyDefinition, new_allowed_values: T.nilable(T::Array[String])).returns(T::Array[String]) }
    def allowed_values_to_remove(definition, new_allowed_values)
      return [] unless new_allowed_values
      return [] unless allowed_values = definition.allowed_values

      allowed_values - new_allowed_values
    end

    sig { returns(T::Array[ValueBase]) }
    memoize def value_rows
      missing_allowed_values_set = @missing_allowed_values.to_set

      T.unsafe(@config.value_class).for_definition(@definition).for_matching_value_strings(@missing_allowed_values)
        .to_a
        .filter { |row| missing_allowed_values_set.include?(row.value) }
    end
  end

  class DefinitionsCollection
    include CustomProperties
    include CustomPropertiesCore

    sig { params(source: PropertySource, config: ICustomPropertiesConfig).void }
    def initialize(source, config)
      @source = source
      @source_type = T.let(@source.is_a?(::Organization) ? "org" : "business", String)
      @config = T.let(config, ICustomPropertiesConfig)

      @definitions = T.let(nil, T.nilable(T::Array[DefinitionBase]))
    end

    sig { returns(T::Array[DefinitionBase]) }
    def resolved_definitions
      definitions.uniq { |d| d.property_name.downcase }
    end

    sig { returns(T::Array[DefinitionBase]) }
    def own_definitions
      definitions.select { |d| d.source_id == @source.id && d.source_type == @source_type }
    end

    sig { returns(Integer) }
    def own_definitions_count
      own_definitions.size
    end

    sig { void }
    def remove_cached_definitions
      @definitions = nil
    end

    private

    sig { returns(T::Array[DefinitionBase]) }
    def definitions
      return @definitions unless @definitions.nil?

      @definitions = T.unsafe(@config.definition_class).for(@source).order(:property_name, source_type: :DESC).to_a
    end
  end
end
