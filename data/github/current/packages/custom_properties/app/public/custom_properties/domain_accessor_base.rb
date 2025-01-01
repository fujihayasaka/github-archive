# typed: strict
# frozen_string_literal: true

module CustomProperties
  module DomainAccessorBase
    extend T::Helpers

    include Kernel
    include CustomPropertiesCore::Errors
    # remove this when DomainAccessorBase is moved to CustomPropertiesCore
    include CustomPropertiesCore

    abstract!

    DESTROY_BATCH_SIZE = 100

    # Checks if the URL type is enabled for the given source. If the source is a standalone org or a business,
    # it is checked directly. If it's an org in a business, the business is checked instead.
    sig { params(source: ::CustomProperties::IPropertySource).returns(T::Boolean) }
    def url_type_enabled?(source)
      if source.is_a?(Organization) && source.business.present?
        FeatureFlag.vexi.enabled?(:custom_properties_url_type, source.business, default: false)
      else
        FeatureFlag.vexi.enabled?(:custom_properties_url_type, source, default: false)
      end
    end

    # Returns whether the actor type is enabled for the org or its owning business.
    sig { params(source: IPropertySource).returns(T::Boolean) }
    def actor_type_enabled?(source)
      if source.is_a?(Organization) && source.business.present?
        FeatureFlag.vexi.enabled?(:custom_properties_actor_type, source.business, default: false)
      else
        FeatureFlag.vexi.enabled?(:custom_properties_actor_type, source, default: false)
      end
    end

    # Read custom property definitions for an org or business.
    #
    # Returns sorted list of definitions
    # If both org and business definitions exist, schema is resolved.
    # Business definitions take precedence over org definitions.
    sig { params(source: PropertySource).returns(T::Array[IPropertyDefinition]) }
    def get_definitions(source)
      definitions_manager(source).get_definitions
    end

    # Read custom property definitions for an org or business.
    #
    # Returns only sorted list of definitions owned by the provided source
    # In case of business, it will return only business definitions.
    # In case of org, it will return only org definitions.
    # WARNING: Unless you have a good reason to use this method such as admin or source specific count, you should always prefer `get_definitions`.
    sig { params(source: PropertySource).returns(T::Array[IPropertyDefinition]) }
    def get_own_definitions(source)
      definitions_manager(source).get_definitions(only_defined_by_source: true)
    end

    # Get definition by property name
    #
    # Returns the definition model or nil if it does not exist
    # If both org and business definitions exist, schema is resolved.
    # Business definitions take precedence over org definitions.
    sig { params(source: PropertySource, property_name: String).returns(T.nilable(IPropertyDefinition)) }
    def get_definition(source, property_name)
      definitions_manager(source).get_definition(property_name)
    end

    # Case insensitive search for definitions with similar name in child orgs
    # Returns a list of definitions.
    sig { params(business: ::Business, property_name: String).returns(T::Array[DefinitionBase]) }
    def child_orgs_definitions_by_name(business, property_name)
      definitions_manager(business).child_orgs_definitions_by_name(property_name)
    end


    # Public: search for property definitions using a standard query syntax
    #
    # q        - The query string
    # page     - The page number to return
    # per_page - The number of items per page
    #
    # Returns a hash with the page of results
    sig do
      params(
        source: PropertySource,
        q: T.nilable(String),
        page: Integer,
        per_page: Integer,
      ).returns(Search::Definitions::MysqlSearch::SearchResult)
    end
    def search_definitions(source, q, page, per_page: Search::Definitions::MysqlSearch::PER_PAGE)
      engine = Search::Definitions::MysqlSearch.new(source, config)
      engine.search(q, page, per_page:)
    end

    sig do
      overridable.params(
        source: PropertySource,
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
    def save_definition(source, property_name:, value_type: "string", required: false, default_value: nil, description: nil, allowed_values: nil, values_editable_by: nil, regex: nil)
      definitions_manager(source).save_definition(
        property_name: property_name,
        value_type: value_type,
        required: required,
        default_value: default_value,
        description: description,
        allowed_values: allowed_values,
        values_editable_by: values_editable_by,
        regex: regex,
      )
    end

    # Delete definition
    #
    # Returns the deleted definition or nil if it did not exist
    sig { overridable.params(source: PropertySource, property_name: String).returns(T.nilable(IPropertyDefinition)) }
    def delete_definition(source, property_name)
      definitions_manager(source).delete_definition(property_name)
    end

    # Promote a property definition from an organization to the enterprise level.
    #
    # Promotion requires using business level definitions manager.
    # Property can be promoted only if there are no other properties with the same name in the enterprise orgs.
    #
    # definition - Org level property definition to promote
    # Returns promoted property definition
    sig { overridable.params(business: ::Business, definition: IPropertyDefinition).returns(IPropertyDefinition) }
    def promote_definition(business, definition)
      definitions_manager(business).promote_definition(definition)
    end

    # Get the usage count of the property definition
    #
    # The count filters targets using the defined target_scope on the value model if it exists
    #
    # Returns the number of targets that use the property
    sig { params(definition: ::CustomProperties::IPropertyDefinition).returns(Integer) }
    def property_usage_count(definition)
      # We want a count of distinct targets, not a count of matching value rows
      relation = T.unsafe(config.value_class).for_definition(definition).select(:target_id).distinct

      if T.unsafe(config.value_class).respond_to?(:target_scope)
        # If the custom properties tables are in the same cluster as the target class,
        # which is the expected case, we can use a join and make one SQL query.
        # Otherwise we need to make separate queries to each cluster to calculate usage.
        target_klass = T.unsafe(config.value_class).target_class_name.constantize
        if target_klass.cluster_name == T.unsafe(config.value_class).cluster_name
          relation = relation.with_target_scope
        else
          # This results in two SQL queries
          # 1. Get potential target ids from values table.
          # 2. Count filtered target_ids using the targets table and the target_scope
          possible_ids = relation.pluck(:target_id)
          target_scope = T.unsafe(config.value_class).target_scope
          relation = target_klass.where(id: possible_ids).instance_exec(&target_scope)
        end
      end

      relation.count
    end

    # Sets the property values for the given entities in the given source.
    #
    # source - the business or organization which the entities belong to
    # entities - the entities to set the properties for
    # properties - hash of property name to values to set on the entities
    sig do
      params(
        source: PropertySource,
        targets: T::Array[IPropertyTarget],
        properties: T::Hash[String, PropertyValue],
      ).void
    end
    def set_properties_for(source, targets, properties)
      values_manager(source).set_properties_for(targets, properties)
    end

    # Retrieve custom properties for given targets.
    #
    # targets - List of targets to retrieve properties for
    # value_to_use - :manual or :effective values.
    #                :manual will return values set explicitly for the target.
    #                :effective will return values set for the target or default value if property is required.
    # strip_nils - If true, will remove nil values from the properties hashes.
    #
    # Returns a hash of target to a hash of property name to value.
    # Targets are the same as the ones passed in.
    sig do
      type_parameters(:T)
        .params(
          targets: T::Enumerable[T.all(T.type_parameter(:T), IPropertyTarget)],
          value_to_use: Symbol,
          strip_nils: T::Boolean
        )
        .returns(T::Hash[T.type_parameter(:T), T::Hash[String, T.nilable(::CustomProperties::PropertyValue)]])
        .checked(:always).on_failure(:raise)
    end
    def values_for_targets(targets, value_to_use:, strip_nils: false)
      allowed_values_to_use = [:manual, :effective]
      unless allowed_values_to_use.include?(value_to_use)
        raise ArgumentError, "invalid value specified for value_to_use: #{value_to_use}"
      end

      target_ids = targets.map(&:properties_target_id).uniq.compact
      org_source_ids = targets.map(&:properties_org_source_id).uniq.compact
      business_source_ids = targets.map(&:properties_business_source_id).uniq.compact

      org_defs_hash = {}
      org_defs_hash = config.definition_class.where(source_id: org_source_ids, source_type: :org).group_by(&:source_id) if org_source_ids.any?

      biz_defs_hash = {}
      biz_defs_hash = config.definition_class.where(source_id: business_source_ids, source_type: :business).group_by(&:source_id) if business_source_ids.any?

      # At this point we don't know if user needs effective or manual value, but we want to provide a consistent order for the values
      set_values_by_target = {}
      set_values_by_target = config.value_class.where(target_id: target_ids).order(value: :asc).group_by(&:target_id) if target_ids.any?

      targets.to_h do |target|
        values_by_definition = T.let(set_values_by_target.fetch(target.properties_target_id, []).group_by(&:definition_id), T::Hash[Integer, T::Array[ValueBase]])

        biz_id = target.properties_business_source_id
        biz_defs = biz_id ? biz_defs_hash.fetch(biz_id, []) : []

        org_id = target.properties_org_source_id
        org_defs = org_id ? org_defs_hash.fetch(org_id, []) : []

        definitions = CustomPropertiesDefinitionsManager.merge_definitions(biz_defs, org_defs)
        properties = definitions.to_h do |defn|
          # check all set values to see if one exists for this definition and target
          values = values_by_definition.fetch(defn.id, [])

          value = if value_to_use == :effective && defn.required? && defn.default_value && values.empty?
            defn.default_value
          else
            manual_values = values.pluck(:value)
            if defn.multi_select_value_type?
              manual_values.empty? ? nil : manual_values
            else
              manual_values.first
            end
          end

          [defn.property_name, value]
        end

        properties = properties.compact if strip_nils

        [target, properties]
      end
    end

    # Case insensitive search for property values that match a search term for a given definition.
    #
    # source - The source to get the definitions manager for
    # property_name  - The name of the property definition to search values for
    # search_term    - The search term to match against property values
    # limit          - Optional maximum number of results to return
    #
    # Returns an array of unique matching property values sorted alphabetically.
    sig do
      params(
        source: PropertySource,
        property_name: String,
        search_term: String,
        limit: T.nilable(Integer)
      ).returns(T::Array[String])
    end
    def search_property_values(source, property_name, search_term, limit: nil)
      values_manager(source).search_property_values(property_name, search_term, limit: limit)
    end

    # Validate values and definitions against the schema for the collection's org
    #
    # source - The source to get the definitions manager for
    # properties - A hash of properties to validate
    #
    # Returns an array of errors. Empty array means that properties are valid.
    sig do
      params(
        source: PropertySource,
        properties: T::Hash[T.any(String, Symbol), PropertyValue]
      ).returns(T::Array[SchemaValidationError])
    end
    def validate_properties(source, properties)
      values_manager(source).validate_properties(properties)
    end

    # Public: Check if a conditions is satisfied by a given set of properties
    #
    # properties - the properties to check
    # conditions - the condition to check
    # match_type - comparison type (e.g. :all, :any)
    #
    # Returns true if the given properties satisfy the condition, false otherwise
    sig do
      params(
        properties: T::Hash[String, T.nilable(PropertyValue)],
        conditions: T::Array[{ name: String, values: T.nilable(T::Array[String]) }],
        match_type: Symbol
      ).returns(T::Boolean)
    end
    def properties_match_conditions?(properties, conditions, match_type: :all) # rubocop:todo Metrics/MethodLength
      raise ArgumentError, "Invalid match_type" unless [:all, :any].include?(match_type)

      properties = properties.transform_keys(&:downcase)
      conditions = conditions.map { |cond| [cond[:name], cond[:values]] }
      if match_type == :any
        conditions.any? { |property_name, expected_values| values_match?(properties[property_name.downcase], expected_values) }
      else
        conditions.all? { |property_name, expected_values| values_match?(properties[property_name.downcase], expected_values) }
      end
    end

    # Standalone validator to check if a provided value is valid given the provided allowed_values
    #
    # This method skips any other validations, and is not meant to provide comprehensive validation.
    # It is a helper that can be used without an instance of a PropertyDefinition or PropertyValue. This is an
    # unlikely scenario, but sometimes needed during creation flows.
    #
    # property_name - used to identify the property in the error messages
    # value_type - the type of the property (e.g. string, single_select, multi_select, or true_false)
    # allowed_values - an array of allowed values for the property
    # value - the value to validate
    sig do
      params(
        property_name: String,
        value_type: String,
        allowed_values: T.nilable(T::Array[String]),
        value: T.untyped
      ).returns(T::Array[CustomPropertiesCore::Errors::SchemaValidationError])
    end
    def validate_allowed_values(property_name:, value_type:, allowed_values:, value:)
      CustomPropertiesValidator.validate_allowed_values(property_name, value_type, allowed_values, value)
    end

    # Public: Delete all property values for a given target
    #
    # target - The target to delete properties for
    sig { params(target: IPropertyTarget).void.checked(:always).on_failure(:raise) }
    def destroy_all_property_values(target)
      config.value_class.where(target_id: target.properties_target_id).destroy_all
    end

    # Public: Delete all property definitions for a given source
    #
    # source - The source to delete definitions for
    sig { params(source: PropertySource).void.checked(:always).on_failure(:raise) }
    def destroy_all_property_definitions(source)
      config.definition_class.transaction do
        T.unsafe(config.definition_class).defined_by(source).in_batches(of: DESTROY_BATCH_SIZE).destroy_all
      end
    end

    # Handle the case when an organization is removed from a business.
    #
    # This method is intended to be called when an organization is removed from an business. Custom property
    # definitions are created in the context of a business or an organization. Objects within an organization inherit
    # the custom property definitions from the business. When an organization is removed from a business, the custom
    # property definitions no longer apply to the organization. This method should be called to handle the removal of
    # values associated to the business definitions from the organization.
    #
    # Each domain accessor is responsible for implementing this method to handle value removal. If none is needed, it
    # can be implemented as a no-op. Search for usages of this method to find examples and integration points.
    #
    # business - The business that the organization was removed from
    # org - The organization that was removed from the business
    sig { abstract.params(business: ::Business, org: ::Organization).void }
    def handle_org_removed_from_business(business:, org:); end

    # Handle the case when an organization is added to a business.
    #
    # This method is intended to be called when an organization is added to a business. Custom property
    # definitions are created in the context of a business or an organization. Objects within an organization inherit
    # the custom property definitions from the business. When an organization is added to a business, the custom
    # property definitions now apply to the organization. This method should be called when an organization is added
    # to a business to run any necessary logic, like handling definition conflicts between the business and the organization.
    #
    # Each domain accessor is responsible for implementing this method. If none is needed, it can be implemented as a
    # no-op. Search for usages of this method to find examples and integration points.
    #
    # business - The business that the organization was added to
    # org - The organization that was added to the business
    sig { abstract.params(business: ::Business, org: ::Organization).void }
    def handle_org_added_to_business(business:, org:); end

    private

    sig do
      params(
        actual_values: T.nilable(PropertyValue),
        expected_values: T.nilable(PropertyValue),
      ).returns(T::Boolean)
    end
    def values_match?(actual_values, expected_values)
      (Array(actual_values).map(&:downcase) & Array(expected_values).map(&:downcase)).present?
    end

    # Returns the configuration settings for the custom properties.
    #
    # Configuration class implementing ICustomPropertiesConfig must be provided by the domain owner
    sig { abstract.returns(CustomPropertiesCore::ICustomPropertiesConfig) }
    def config; end

    # This is a memoized method that returns the definitions manager for the given source.
    # It will return a new instance of the definitions manager if the source has changed.
    #
    # This module is used in domain accessors which are instantiated per request context.
    # Custom properties are typically used in the context of a single source (e.g. an organization or a business)
    # per request context. As such, we can generally assume we will not be reinstantiating the manager multiple times
    # per request context. If we find the usage pattern to change, we can consider a hash of managers per source.
    #
    # @param source [PropertySource] The source to get the definitions manager for.
    # @return [IDefinitionsManager] The definitions manager for the given source.
    sig { params(source: PropertySource).returns(IDefinitionsManager) }
    def definitions_manager(source)
      if @source != source
        @source = T.let(nil, T.nilable(PropertySource))
        @definitions_manager = T.let(nil, T.nilable(CustomPropertiesDefinitionsManager))
      end

      @definitions_manager ||= if source.is_a?(Organization)
        CustomPropertiesDefinitionsManager.new(source, config)
      else
        CustomPropertiesBusinessDefinitionsManager.new(source, config)
      end

      @source = source
      @definitions_manager
    end

    # This is a memoized method that returns the values manager for the given source.
    # It will return a new instance of the values manager if the source has changed.
    #
    # This module is used in domain accessors which are instantiated per request context.
    # Custom properties are typically used in the context of a single source (e.g. an organization or a business)
    # per request context. As such, we can generally assume we will not be reinstantiating the manager multiple times
    # per request context. If we find the usage pattern to change, we can consider a hash of managers per source.
    #
    # @param source [PropertySource] The source to get the definitions manager for.
    # @return [IValuesManager] The values manager for the given source.
    sig { params(source: PropertySource).returns(IValuesManager) }
    def values_manager(source)
      if @source != source
        @values_manager = T.let(nil, T.nilable(CustomPropertiesValuesManager))
      end

      @values_manager ||= CustomPropertiesValuesManager.new(T.cast(definitions_manager(source), CustomPropertiesDefinitionsManager))
    end
  end
end
