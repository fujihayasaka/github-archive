# typed: strict
# frozen_string_literal: true

class CustomPropertiesDefinitionsManager
  include CustomProperties
  include CustomProperties::Errors
  include GitHub::Memoizer

  # Public: Initializes a new instance to handle the properties for an org
  #
  # source - The org or business to handle properties for
  sig { params(source: PropertySource).void }
  def initialize(source)
    if self.instance_of?(CustomPropertiesDefinitionsManager)
      raise ArgumentError.new "Avoid using 'CustomPropertiesDefinitionsManager' unless working with 'Organization' source" unless source.is_a?(Organization)
    end

    @source = source
    @source_type = T.let(@source.is_a?(::Organization) ? "org" : "business", String)
    @definitions_collection = T.let(DefinitionsCollection.new(@source), DefinitionsCollection)
  end

  # Public returns the organization to which the collection belongs, or nil if this manager is initialized with an enterprise
  sig { returns(T.nilable(::Organization)) }
  def organization
    return nil if @source.is_a?(::Business)
    @source
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
  sig { params(only_defined_by_source: T::Boolean).returns(T::Array[IPropertyDefinition]) }
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
  sig { params(property_name: String).returns(T.nilable(IPropertyDefinition)) }
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
    params(
      property_name: String,
      value_type: String,
      required: T::Boolean,
      default_value: T.nilable(PropertyValue),
      description: T.nilable(String),
      allowed_values: T.nilable(T::Array[String]),
      values_editable_by: T.nilable(String),
      regex: T.nilable(String)
    ).returns(IPropertyDefinition)
  end
  def save_definition(property_name:, value_type: "string", required: false, default_value: nil, description: nil, allowed_values: nil, values_editable_by: "org_actors", regex: nil)
    definition = find_definition_by_name(@definitions_collection.resolved_definitions, property_name)
    if definition
      raise_if_wrong_source_type!(definition)
      raise_if_value_type_changed!(definition, value_type)

      usages_checker = AllowedUsagesValueChecker.new(definition, allowed_values)
      usages_checker.check!

      has_to_reindex_repos = definition.required != required || definition.default_value != default_value

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

      has_to_reindex_repos = required

      definition = CustomPropertyDefinition.create!(
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
    reindex_org_repos if has_to_reindex_repos
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
  sig { params(property_name: String).returns(T.nilable(IPropertyDefinition)) }
  def delete_definition(property_name)
    definition = find_definition_by_name(@definitions_collection.own_definitions, property_name)

    return nil unless definition
    raise_if_wrong_source_type!(definition)

    safe_destroy!(definition)

    reindex_org_repos
    @definitions_collection.remove_cached_definitions

    definition
  end

  # Merges org and business definitions, ensuring that business definitions take precedence over org definitions.
  # Returns a new array of definitions sorted by property name.
  sig { params(business_defs: T::Array[CustomPropertyDefinition], org_defs: T::Array[CustomPropertyDefinition]).returns(T::Array[CustomPropertyDefinition]) }
  def self.merge_definitions(business_defs, org_defs)
    biz_prop_names_set = business_defs.map { |defn| defn.property_name.downcase }.to_set
    org_defs = org_defs.filter { |defn| !biz_prop_names_set.include?(defn.property_name.downcase) }

    (org_defs + business_defs).sort_by { |defn| defn.property_name.downcase }
  end

  # Public: replaces usages for a given consumer
  #
  # consumer_type - a consumer type. One of [:ruleset]
  # consumer_id - The id of the consumer
  # conditions - List of conditions to save.
  sig { params(consumer_type: Symbol, consumer_id: T.any(Integer, String), conditions: T::Array[[String, String]]).void }
  def register_usage(consumer_type, consumer_id, conditions)
    Repository.transaction do
      delete_usages(consumer_type, consumer_id)

      conditions.uniq.each do |property_name, property_value|
        definition = find_definition_by_name(@definitions_collection.resolved_definitions, property_name.to_s)
        raise ArgumentError, "Property '#{property_name}' is not defined" unless definition

        CustomPropertyUsage.create!(
          definition_id: definition.id,
          consumer_id: consumer_id,
          consumer_type: consumer_type,
          property_value: property_value
        )
      end
    rescue ActiveRecord::RecordInvalid => exception
      raise InvalidPropertyUsage.new exception.message
    end
  end

  # Public: delete usages for given consumers
  #
  # consumer_type - a consumer type. One of [:ruleset]
  # consumer_ids - The ids of the consumers to delete usages for
  sig { params(consumer_type: Symbol, consumer_ids: T.any(Integer, String)).void }
  def delete_usages(consumer_type, *consumer_ids)
    CustomPropertyUsage
      .includes(:definition)
      .where(
        consumer_id: consumer_ids,
        consumer_type: consumer_type,
        definition: { source_id: @source.id, source_type: @source_type }
      )
      .destroy_all
  end

  # Public: get a list of usages for a given property or combination of property and property value.
  # List is limited to 50 items.
  #
  # property_name - Name of the property
  # property_value - Value of the property. If nil, all usages of the property name will be returned
  #
  # If no matches empty array will be returned.
  sig do
    params(
      property_name: String,
      property_value: T.nilable(String)
    ).returns(T::Array[IPropertyUsage])
  end
  def get_condition_usages(property_name, property_value: nil)
    usages = CustomPropertyUsage
      .includes(:definition)
      .where(definition: { source_id: @source.id, source_type: @source_type, property_name: property_name })
    usages = usages.where(property_value: property_value) unless property_value.nil?

    usages.limit(50).to_a
  end

  private

  # Case insensitive search for a definition by property name
  sig { params(definitions: T::Array[CustomPropertyDefinition], property_name: String).returns(T.nilable(CustomPropertyDefinition)) }
  def find_definition_by_name(definitions, property_name)
    definitions.find { |d| d.property_name.downcase == property_name.downcase }
  end

  sig { void }
  def reindex_org_repos
    if @source.is_a?(::Business)
      BulkReposIndexJob.reindex_business(@source)
    else
      BulkReposIndexJob.reindex_org(@source.id)
    end
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

  sig { params(definition: CustomPropertyDefinition).void }
  def safe_destroy!(definition)
    begin
      definition.destroy!
    rescue ActiveRecord::RecordNotDestroyed
      raise DefinitionDeletionError.new(
        "Property definition '#{definition.property_name}' has usages and cannot be deleted"
      )
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

    sig { params(definition: IPropertyDefinition, new_allowed_values: T.nilable(T::Array[String])).void }
    def initialize(definition, new_allowed_values)
      @definition = definition
      @missing_allowed_values = T.let(allowed_values_to_remove(definition, new_allowed_values), T::Array[String])
    end

    # Public: Checks if the allowed values to be deleted are in use by any repo.
    # Usages from inactive repos (soft-deleted) are not considered.
    # Raises a DefinitionDeletionAllowValueInUseError with a descriptive message.
    sig { void }
    def check!
      return if @missing_allowed_values.empty?
      return if value_rows.empty?

      repo_count = Repository.active.where(id: value_rows.pluck(:target_id).compact).count
      return if repo_count.zero?

      values_with_commas = @missing_allowed_values.sort.map { |value| "'#{value}'" }.join(", ")
      allowed_values_text = "#{values_with_commas} referenced by #{repo_count} active #{"repository".pluralize(repo_count)}"
      message = "Unable to save '#{@definition.property_name}' because you can't delete options that are in use: #{allowed_values_text}."
      raise CustomProperties::Errors::DefinitionDeletionAllowValueInUseError.new message
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

    sig { returns(T::Array[CustomPropertyValue]) }
    memoize def value_rows
      missing_allowed_values_set = @missing_allowed_values.to_set
      CustomPropertyValue
       .where(definition: @definition, value: @missing_allowed_values)
       .to_a
       .filter { |row| missing_allowed_values_set.include?(row.value) }
    end
  end

  class DefinitionsCollection
    include CustomProperties

    sig { params(source: PropertySource).void }
    def initialize(source)
      @source = source
      @source_type = T.let(@source.is_a?(::Organization) ? "org" : "business", String)

      @definitions = T.let(nil, T.nilable(T::Array[CustomPropertyDefinition]))
    end

    sig { returns(T::Array[CustomPropertyDefinition]) }
    def resolved_definitions
      definitions.uniq { |d| d.property_name.downcase }
    end

    sig { returns(T::Array[CustomPropertyDefinition]) }
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

    sig { returns(T::Array[CustomPropertyDefinition]) }
    def definitions
      return @definitions unless @definitions.nil?

      @definitions = CustomPropertyDefinition.for(@source).order(:property_name, source_type: :DESC).to_a
    end
  end
end
