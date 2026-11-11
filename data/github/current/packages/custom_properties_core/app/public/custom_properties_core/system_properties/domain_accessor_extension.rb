# typed: strict
# frozen_string_literal: true

module CustomPropertiesCore
  module SystemProperties
    module DomainAccessorExtension
      extend T::Helpers

      include CustomPropertiesCore::Errors

      requires_ancestor { DomainAccessorBase }

      abstract!

      # Returns whether the runtime-risk system property is enabled for the given organization or business.
      sig { params(source: IPropertySource).returns(T::Boolean) }
      def runtime_risk_system_property_enabled?(source)
        if source.is_a?(Organization)
          FeatureFlag.vexi.enabled?(:custom_properties_system_properties_runtime_risk, source, source.business, default: false)
        else
          FeatureFlag.vexi.enabled?(:custom_properties_system_properties_runtime_risk, source, default: false)
        end
      end

      # Returns the list of enabled system property names for the given source.
      sig { params(source: IPropertySource).returns(T::Array[String]) }
      def system_property_names(source)
        names = system_property_definitions.map(&:property_name)
        names.reject! { |name| name == "runtime-risk" } unless runtime_risk_system_property_enabled?(source)
        names
      end

      # Sets system property values for the given targets
      #
      # targets - the targets to set the properties for
      # properties - a hash of system property names to their values to set
      sig do
        params(
          targets: T::Array[IPropertyTarget],
          properties: T::Hash[String, T.nilable(PropertyValue)],
        ).void.checked(:always).on_failure(:raise)
      end
      def set_system_properties_for(targets, properties)
        system_value_class = config_extension.system_value_class
        target_class_name = T.let(T.unsafe(system_value_class).target_class_name, String)
        malformed_target_types = T.let(
          targets.select { |target| target.class.name != target_class_name }
          .map { |target| target.class.name }
          .uniq, T::Array[String]
        )
        if malformed_target_types.any?
          raise ArgumentError,
            "Invalid target: Targets with type #{malformed_target_types.join(", ")} don't match system property value target type #{target_class_name}."
        end

        assert_no_validation_errors!(properties)

        # Definition name is validated above so we can assume its existence here
        # Map actual defintion ids to the incoming case insensitive property names for easier lookup in the query below
        definition_ids_hash = properties.to_h { |name, _| [find_system_property_definition!(name).id, name] }

        system_value_class.transaction do
          # map of target_id to array of system property values for the given definition ids
          entities_values_hash = T.unsafe(system_value_class).for_target_ids(targets.map(&:properties_target_id)).for_definition_ids(definition_ids_hash.keys).group_by(&:target_id)

          targets.each do |target|
            # map incoming case insensitive property names to the existing system property value rows for the target
            # this allows us to handle updates and deletes for existing values regardless of the case of the
            # incoming property name
            name_to_rows_group = (entities_values_hash[target.properties_target_id] || []).group_by do |row|
              definition_id = T.unsafe(system_value_class).definition_ids[row.definition_id]
              T.must(definition_ids_hash[definition_id])
            end
            delete_properties = T.let([], T::Array[SystemProperties::ValueBase])
            create_properties = T.let([], T::Array[[String, String]])

            properties.each_pair do |name, values|
              values = Array(values).compact_blank
              rows = name_to_rows_group.fetch(name, [])
              values_to_create = values - rows.map(&:value)
              rows_to_delete = rows.filter { |row| !values.include?(row.value) }

              delete_properties += rows_to_delete
              create_properties += values_to_create.map { |value| [name, value] }
            end

            delete_properties.each { |row| row.destroy! }
            create_properties.each do |name, value|
              system_value_class.create!(
                target_id: target.properties_target_id,
                definition_id: find_system_property_definition!(name).id,
                value: value
              )
            end
          end
        end
      end

      # Retrieve system properties for given targets.
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
          .returns(T::Hash[T.type_parameter(:T), T::Hash[String, T.nilable(PropertyValue)]])
          .checked(:always).on_failure(:raise)
      end
      def system_property_values_for_targets(targets, value_to_use:, strip_nils: false)
        allowed_values_to_use = [:manual, :effective]
        unless allowed_values_to_use.include?(value_to_use)
          raise ArgumentError, "invalid value specified for value_to_use: #{value_to_use}"
        end

        target_ids = targets.map(&:properties_target_id).uniq.compact

        system_value_class = config_extension.system_value_class

        definitions = system_property_definitions
        set_values_by_target = T.let({}, T::Hash[Integer, T::Array[ValueBase]])
        set_values_by_target = system_value_class.where(target_id: target_ids).order(value: :asc).group_by(&:target_id) if target_ids.any?

        targets.to_h do |target|
          values_by_definition = T.let(set_values_by_target.fetch(target.properties_target_id, []).group_by(&:definition_id), T::Hash[String, T::Array[ValueBase]])

          properties = definitions.to_h do |defn|
            # check all set values to see if one exists for this definition and target
            values = values_by_definition.fetch(defn.property_name, [])

            value = if value_to_use == :effective && defn.required && defn.default_value && values.empty?
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

      # Public: Delete all system property values for a given target
      #
      # target - The target to delete system properties for
      sig { params(target: IPropertyTarget).void.checked(:always).on_failure(:raise) }
      def destroy_all_system_property_values(target)
        system_value_class = config_extension.system_value_class

        system_value_class.where(target_id: target.properties_target_id).destroy_all
      end

      sig { abstract.returns(T::Array[Definition]) }
      def system_property_definitions; end

      private

      sig { returns(ICustomPropertiesConfigExtension) }
      def config_extension
        cfg = config
        raise NotImplementedError, "System properties are not supported for this domain" unless cfg.is_a?(ICustomPropertiesConfigExtension)
        cfg
      end

      sig { params(property_name: String).returns(Definition) }
      def find_system_property_definition!(property_name)
        definition = system_property_definitions.find { |defn| defn.property_name.downcase == property_name.downcase }
        raise ArgumentError, "Invalid system property name: #{property_name}" if definition.nil?

        definition
      end

      sig { params(properties: T::Hash[String, T.nilable(PropertyValue)]).returns(T.nilable(PropertyValidationError)) }
      def assert_no_validation_errors!(properties)
        errors = CustomPropertiesValidator.validate_properties(system_property_definitions, properties, limits: CustomPropertiesValidator.system_property_limits)
        raise PropertyValidationError.new(errors) if errors.any?
      end
    end
  end
end
