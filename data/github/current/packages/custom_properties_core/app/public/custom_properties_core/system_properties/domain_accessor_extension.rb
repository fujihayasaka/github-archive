# typed: strict
# frozen_string_literal: true

module CustomPropertiesCore
  module SystemProperties
    module DomainAccessorExtension
      extend T::Helpers

      include CustomPropertiesCore::Errors

      requires_ancestor { DomainAccessorBase }

      # Returns whether system properties are enabled for the given organization or business.
      sig { params(source: IPropertySource).returns(T::Boolean) }
      def system_properties_enabled?(source)
        if source.is_a?(Organization) && source.business.present?
          FeatureFlag.vexi.enabled?(:custom_properties_system_properties, source.business, default: false) ||
          FeatureFlag.vexi.enabled?(:custom_properties_system_properties, source, default: false)
        else
          FeatureFlag.vexi.enabled?(:custom_properties_system_properties, source, default: false)
        end
      end

      # Sets the system property value for the given entities
      #
      # Single value due to complexity of validation
      #
      # entities - the entities to set the properties for
      # property_name - the name of the system property to set
      # value - the value to set for the system property
      # value_type - One of "string", "single_select", "true_false", "multi_select", or "url". Used for validation.
      # allowed_values - Optional: The allowed values for the system property. Used for validation.
      sig do
        params(
          targets: T::Array[IPropertyTarget],
          property_name: String,
          value: T.nilable(PropertyValue),
          value_type: String,
          allowed_values: T.nilable(T::Array[String]),
        ).void.checked(:always).on_failure(:raise)
      end
      def set_system_properties_for(targets, property_name, value, value_type: "string", allowed_values: nil)
        # This is very similar to set_properties_for in CustomPropertiesValuesManager,
        # We should see if we can consolidate the logic in the future when we extract
        # System Properties into this module.

        system_value_class = config.system_value_class
        if system_value_class.nil?
          raise NotImplementedError, "System properties are not supported for this target"
        end

        target_class_name = T.let(T.unsafe(system_value_class).target_class_name, String)
        malformed_entity_types = T.let(
          targets.select { |entity| entity.class.name != target_class_name }
          .map { |entity| entity.class.name }
          .uniq, T::Array[String]
        )
        if malformed_entity_types.any?
          raise ArgumentError,
            "Invalid entity: Entities with type #{malformed_entity_types.join(", ")} don't match system property value target type #{target_class_name}."
        end

        errors = CustomPropertiesValidator.validate_system_property(property_name, value_type, allowed_values, value)
        raise PropertyValidationError.new(errors) if errors.any?

        # Definition name is validated above so we can assume its existence here
        definition_id = T.unsafe(system_value_class).definition_ids[property_name]

        system_value_class.transaction do
          entities_values_hash = T.unsafe(system_value_class).for_target_ids(targets.map(&:properties_target_id)).for_definition_ids(definition_id).group_by(&:target_id)

          targets.each do |target|
            rows = (entities_values_hash[target.properties_target_id] || [])
            delete_properties = T.let([], T::Array[SystemProperties::ValueBase])

            values = T.let(Array(value).compact_blank, T::Array[String])
            values_to_create = values - rows.map(&:value)
            rows_to_delete = rows.filter { |row| !values.include?(row.value) }

            delete_properties += rows_to_delete

            delete_properties.each { |row| row.destroy! }
            values_to_create.each do |value|
              system_value_class.create!(
                target_id: target.properties_target_id,
                definition_id: definition_id,
                value: value
              )
            end
          end
        end
      end

      # Retrieve system properties for given targets.
      #
      # targets - List of targets to retrieve properties for
      # strip_nils - If true, will remove nil values from the properties hashes.
      #
      # Returns a hash of target to a hash of property name to value.
      # Targets are the same as the ones passed in.
      sig do
        type_parameters(:T)
          .params(
            targets: T::Enumerable[T.all(T.type_parameter(:T), IPropertyTarget)],
            strip_nils: T::Boolean
          )
          .returns(T::Hash[T.type_parameter(:T), T::Hash[String, T.nilable(PropertyValue)]])
          .checked(:always).on_failure(:raise)
      end
      def system_property_values_for_targets(targets, strip_nils: false)
        target_ids = targets.map(&:properties_target_id).uniq.compact

        system_value_class = config.system_value_class
        if system_value_class.nil?
          raise NotImplementedError, "System properties are not supported for this target"
        end

        # If we support default values for system properties, we will need to move this check
        # down to where we fetch values_by_definition.
        # See values_for_targets method for reference.
        return {} if target_ids.empty?

        track("system_values_for_targets") do
          set_values_by_target = system_value_class.where(target_id: target_ids).order(value: :asc).group_by(&:target_id)

          targets.to_h do |target|
            values_by_definition = set_values_by_target.fetch(target.properties_target_id, []).group_by(&:definition_id)

            definitions = T.let(T.unsafe(system_value_class).definition_ids, T::Hash[T.any(String, Symbol), Integer])
            properties = definitions.to_h do |defn|
              # check all set values to see if one exists for this definition and target
              values = values_by_definition.fetch(defn, [])

              # We do not have definitions for system properties, so we do not know if this is a multi select property
              # or not. We will return an array if there are multiple values in the DB, otherwise we will return a single
              # string or nil. The caller will need to handle this accordingly. If we move system properties into this
              # package, then we can revisit this and return consistent types based on the definition value type.
              value = T.let(values.count > 1 ? values.pluck(:value) : values.first&.value, T.nilable(PropertyValue))

              [defn.to_s, value]
            end

            properties = properties.compact if strip_nils

            [target, properties]
          end
        end
      end

      # Public: Delete all system property values for a given target
      #
      # target - The target to delete system properties for
      sig { params(target: IPropertyTarget).void.checked(:always).on_failure(:raise) }
      def destroy_all_system_property_values(target)
        system_value_class = config.system_value_class
        if system_value_class.nil?
          raise NotImplementedError, "System properties are not supported for this target"
        end

        system_value_class.where(target_id: target.properties_target_id).destroy_all
      end
    end
  end
end
