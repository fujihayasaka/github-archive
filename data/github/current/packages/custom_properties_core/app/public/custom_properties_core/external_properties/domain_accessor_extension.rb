# typed: strict
# frozen_string_literal: true

module CustomPropertiesCore
  module ExternalProperties
    module DomainAccessorExtension
      extend T::Helpers

      include CustomPropertiesCore::Errors

      requires_ancestor { DomainAccessorBase }

      # Returns all external property definitions for the given source.
      #
      # source       - The organization or business to scope definitions to
      # namespace_id - The namespace to scope definitions to (optional; when nil, returns all namespaces)
      #
      # Returns a hash of namespace_id to sorted array of definitions.
      sig { params(source: PropertySource, namespace_id: T.nilable(Integer)).returns(T::Hash[String, T::Array[IPropertyDefinition]]) }
      def get_external_property_definitions(source, namespace_id: nil)
        track("get_external_property_definitions", tags: config.additional_tracking_tags(source)) do
          external_definitions_manager(source).get_definitions(namespace_id)
        end
      end

      # Returns a single external property definition by name, or nil if not found.
      #
      # source       - The organization or business to scope definitions to
      # namespace_id - The namespace to scope definitions to
      # property_name - The name of the property to look up
      sig { params(source: PropertySource, namespace_id: Integer, property_name: String).returns(T.nilable(IPropertyDefinition)) }
      def get_external_property_definition(source, namespace_id, property_name)
        track("get_external_property_definition", tags: config.additional_tracking_tags(source)) do
          external_definitions_manager(source).get_definition(namespace_id, property_name)
        end
      end

      # Deletes all external property definitions (and their associated values) for the given source and integration installation.
      #
      # source                   - The organization or business that owns the definitions
      # integration_installation - The integration installation to delete definitions for
      sig { params(source: PropertySource, integration_installation: IntegrationInstallation).void }
      def destroy_all_external_properties_for_integration(source, integration_installation)
        track("destroy_all_external_properties_for_integration", tags: config.additional_tracking_tags(source)) do
          config_extension.external_value_class.transaction do
            namespaces = T.unsafe(config_extension.external_namespace_class)
              .defined_by(source)
              .where(integration_id: integration_installation.integration_id)

            # Use association-based cascading deletes so dependent callbacks run.
            namespaces.destroy_all
          end
        end
      end

      # Deletes all external property definitions (and their associated values) and namespaces
      # owned by the given source.
      #
      # source - The organization or business whose definitions and namespaces should be deleted
      sig { params(source: PropertySource).void }
      def delete_all_external_properties_for_source(source)
        track("delete_all_external_properties_for_source", tags: config.additional_tracking_tags(source)) do
          config_extension.external_value_class.transaction do
            namespace_ids = T.unsafe(config_extension.external_namespace_class).defined_by(source).select(:id)
            definition_ids = config_extension.external_definition_class.where(namespace_id: namespace_ids).select(:id)

            # Bottom-up: values -> definitions -> namespaces
            config_extension.external_value_class.where(definition_id: definition_ids).delete_all
            config_extension.external_definition_class.where(namespace_id: namespace_ids).delete_all
            T.unsafe(config_extension.external_namespace_class).defined_by(source).delete_all
          end
        end
      end

      # Sets external property values for the given targets.
      #
      # External property values are always strings. A nil value will delete the existing value for that property.
      #
      # integration_installation  - The installation integration that is setting the properties
      # targets                   - The targets to set the properties for
      # properties                - A hash of property names to string values (nil to delete)
      sig do
        params(
          integration_installation: IntegrationInstallation,
          targets: T::Array[IPropertyTarget],
          properties: T::Hash[String, T.nilable(String)],
        ).void.checked(:always).on_failure(:raise)
      end
      def set_external_properties_for(integration_installation, targets, properties)
        # Temporarily scope to organization-installed installations
        source = integration_installation.organization
        if !source
          # TODO: loosen this requirement to also allow setting external properties for business-installed integrations
          raise ArgumentError, "Integration installation #{integration_installation.id} is not associated with an organization, which is required to set external properties"
        end

        track("set_external_properties_for", tags: (config.additional_tracking_tags(source) || {}).merge(
          integration_id: integration_installation.integration_id.to_s,
        )) do
          namespace = find_namespace(integration_installation, source)

          # Start the transaction here so definition creation and cleanup are also part of the transaction and rollback
          config_extension.external_value_class.transaction do
            definitions = find_or_create_definitions(namespace, properties)
            assert_no_external_property_validation_errors!(definitions, properties)

            definitions_by_name = definitions.index_by { |d| d.property_name.downcase }
            target_ids = targets.map(&:properties_target_id)
            definition_ids = definitions_by_name.values.map(&:id)

            existing_values = T.unsafe(config_extension.external_value_class)
              .for_target_ids(target_ids)
              .for_definition_ids(definition_ids)
              .group_by(&:target_id)

            GitHub::PrefillAssociations.prefill_associations(existing_values.values.flatten, :definition, available_records: definitions)

            # We need to clean up any definitions that no longer have value rows
            # We will track any definitions associated with deleted values and delete them if necessary.
            deleted_values_definition_ids = T.let(Set.new, T::Set[Integer])

            targets.each do |target|
              target_values = existing_values.fetch(target.properties_target_id, [])
                .index_by(&:definition_id)

              properties.each do |name, value|
                value = nil if value.blank?
                definition = definitions_by_name[name.downcase]
                next unless definition

                existing = target_values[definition.id]

                if value.nil?
                  existing&.destroy!
                  deleted_values_definition_ids.add(definition.id) if existing
                elsif existing
                  existing.update!(value: value) if existing.value != value
                else
                  config_extension.external_value_class.create!(
                    target_id: target.properties_target_id,
                    definition: definition,
                    value: value,
                  )
                end
              end
            end

            cleanup_orphaned_definitions(definitions.select { |d| deleted_values_definition_ids.include?(d.id) })
          end
        end
      end

      # Retrieves external property values for the given targets.
      #
      # targets      - List of targets to retrieve properties for
      # namespace_id - The namespace to scope definitions to (optional; when nil, returns all namespaces)
      # strip_nils   - If true, properties with nil values will be omitted from the result
      #
      # Returns a hash of target to {namespace_id => {prop_name => value}}.
      sig do
        type_parameters(:T)
          .params(
            targets: T::Enumerable[T.all(T.type_parameter(:T), IPropertyTarget)],
            namespace_id: T.nilable(Integer),
            strip_nils: T::Boolean,
          )
          .returns(T::Hash[T.type_parameter(:T), T::Hash[String, T::Hash[String, T.nilable(String)]]])
          .checked(:always).on_failure(:raise)
      end
      def external_property_values_for_targets(targets, namespace_id: nil, strip_nils: false)
        track("external_property_values_for_targets") do
          ext_config = config_extension
          ext_namespace_class = ext_config.external_namespace_class
          ext_def_class = ext_config.external_definition_class
          ext_val_class = ext_config.external_value_class

          target_ids = targets.map(&:properties_target_id).uniq.compact
          org_source_ids = targets.map(&:properties_org_source_id).uniq.compact
          business_source_ids = targets.map(&:properties_business_source_id).uniq.compact

          org_defs_hash = T.let({}, T::Hash[Integer, T::Array[T.untyped]])
          biz_defs_hash = T.let({}, T::Hash[Integer, T::Array[T.untyped]])
          set_values_by_target = T.let({}, T::Hash[Integer, T::Array[T.untyped]])

          if org_source_ids.any?
            org_namespaces_scope = T.unsafe(ext_namespace_class).for_org_ids(org_source_ids)
            org_namespaces_scope = org_namespaces_scope.where(id: namespace_id) if namespace_id.present?
            org_namespaces = org_namespaces_scope.to_a
            org_defs = T.unsafe(ext_def_class).for_namespace_ids(org_namespaces.map(&:id)).to_a
            GitHub::PrefillAssociations.prefill_associations(org_defs, :namespace, available_records: org_namespaces)
            org_defs_hash = org_defs.group_by(&:source_id)
          end

          if business_source_ids.any?
            biz_namespaces_scope = T.unsafe(ext_namespace_class).for_business_ids(business_source_ids)
            biz_namespaces_scope = biz_namespaces_scope.where(id: namespace_id) if namespace_id.present?
            biz_namespaces = biz_namespaces_scope.to_a
            biz_defs = T.unsafe(ext_def_class).for_namespace_ids(biz_namespaces.map(&:id)).to_a
            GitHub::PrefillAssociations.prefill_associations(biz_defs, :namespace, available_records: biz_namespaces)
            biz_defs_hash = biz_defs.group_by(&:source_id)
          end

          set_values_by_target = T.unsafe(ext_val_class).for_target_ids(target_ids).order(value: :asc).group_by(&:target_id) if target_ids.any?

          targets.to_h do |target|
            target_value_records = set_values_by_target.fetch(target.properties_target_id, [])
              .index_by(&:definition_id)

            biz_id = target.properties_business_source_id
            biz_defs = biz_id ? biz_defs_hash.fetch(biz_id, []) : []

            org_id = target.properties_org_source_id
            org_defs = org_id ? org_defs_hash.fetch(org_id, []) : []

            definitions = ExternalPropertiesDefinitionsManager.merge_definitions(biz_defs, org_defs)
            definitions_by_namespace = T.unsafe(definitions).group_by { |d| d.namespace.display_name }

            ns_hash = definitions_by_namespace.to_h do |ns_name, ns_definitions|
              properties = ns_definitions.to_h do |defn|
                value_record = target_value_records[defn.id]
                [defn.property_name, value_record&.value]
              end

              properties = properties.compact if strip_nils
              [ns_name, properties]
            end

            [target, ns_hash]
          end
        end
      end

      # Deletes all external property values for a given target and cleans up any
      # definitions that no longer have associated values.
      #
      # target - The target to delete external property values for
      sig { params(target: IPropertyTarget).void.checked(:always).on_failure(:raise) }
      def destroy_all_external_property_values(target)
        destroyed_values = T.unsafe(config_extension.external_value_class)
          .for_target(target)
          .includes(:definition) # definitions are needed for instrumentation, so prefill them to avoid N+1
          .destroy_all
        return if destroyed_values.empty?

        definitions = destroyed_values.map(&:definition)
        cleanup_orphaned_definitions(definitions)
      end

      # Deletes external property values for a given target that come from
      # definitions under namespaces defined by the given source.
      #
      # target - The target to delete external property values for
      # source - The organization or business that owns the namespaces under which values should be deleted
      sig do
        params(
          target: IPropertyTarget,
          source: PropertySource,
        ).void.checked(:always).on_failure(:raise)
      end
      def destroy_external_property_values_for_source(target, source)
        namespaces = T.unsafe(config_extension.external_namespace_class).defined_by(source).to_a
        return if namespaces.empty?

        definitions = T.unsafe(config_extension.external_definition_class).for_namespace_ids(namespaces.map(&:id)).to_a
        return if definitions.empty?

        GitHub::PrefillAssociations.prefill_associations(definitions, :namespace, available_records: namespaces)

        deleted_definition_ids = T.let(Set.new, T::Set[Integer])
        T.unsafe(config_extension.external_value_class)
                  .for_target(target)
                  .for_definition_ids(definitions.map(&:id))
                  .in_batches(of: 100) do |batch_relation|
          values_to_destroy = batch_relation.to_a
          GitHub::PrefillAssociations.prefill_associations(values_to_destroy, :definition, available_records: definitions)
          destroyed_values = values_to_destroy.each(&:destroy)
          deleted_definition_ids.merge(destroyed_values.map(&:definition_id))
        end

        cleanup_orphaned_definitions(definitions.select { |d| deleted_definition_ids.include?(d.id) })
      end

      private

      sig { returns(ICustomPropertiesConfigExtension) }
      def config_extension
        cfg = config
        raise NotImplementedError, "External properties are not supported for this domain" unless cfg.is_a?(ICustomPropertiesConfigExtension)
        cfg
      end

      sig { params(definitions: T::Array[IPropertyDefinition], properties: T::Hash[String, T.nilable(String)]).void }
      def assert_no_external_property_validation_errors!(definitions, properties)
        errors = CustomPropertiesValidator.validate_properties(definitions, properties, limits: CustomPropertiesValidator.external_property_limits)
        raise PropertyValidationError.new(errors) if errors.any?
      end

      # Returns a memoized ExternalPropertiesDefinitionsManager for the given source.
      # Follows the same memoization pattern as DomainAccessorBase#definitions_manager.
      sig { params(source: PropertySource).returns(ExternalPropertiesDefinitionsManager) }
      def external_definitions_manager(source)
        if @external_source != source
          @external_source = T.let(nil, T.nilable(PropertySource))
          @external_definitions_manager = T.let(nil, T.nilable(ExternalPropertiesDefinitionsManager))
        end

        @external_definitions_manager ||= ExternalPropertiesDefinitionsManager.new(source, config_extension)
        @external_source = source
        @external_definitions_manager
      end

      # Finds a namespace for the given integration installation and source.
      sig do
        params(
          integration_installation: IntegrationInstallation,
          source: PropertySource
        ).returns(NamespaceBase)
      end
      def find_namespace(integration_installation, source)
        # Temporarily create namespaces as needed until we design a registration flow
        #
        # To support Port, we will force the display name to "Port" by default
        # If the following FF is enabled, we will generate the display name from the integration slug.
        #
        # Display name will be generated using the integration slug, with non-alphanumeric
        # characters removed and a maximum length of MAX_NAMESPACE_DISPLAY_NAME_LENGTH characters.
        display_name = if external_properties_dynamic_naming_enabled?(source)
          T.must(integration_installation.integration).slug.gsub(/[^a-zA-Z0-9]/, "")[0, Public::MAX_NAMESPACE_DISPLAY_NAME_LENGTH]
        else
          "Port"
        end

        namespace = T.unsafe(config_extension.external_namespace_class)
          .defined_by(source)
          .find_or_create_by!(integration_id: integration_installation.integration_id) do |ns|
            ns.display_name = display_name
          end

        # Once we ship a registration flow, this method should look more like the following code:

        # namespace = T.unsafe(config_extension.external_namespace_class)
        #   .defined_by(source)
        #   .find_by(integration_id: integration_installation.integration_id)

        # if namespace.nil?
        #   raise ArgumentError, "No external properties namespace found for integration #{integration_installation.integration_id} on #{source.class.name} #{source.id}"
        # end

        namespace
      end

      sig do
        params(
          namespace: NamespaceBase,
          properties: T::Hash[String, T.nilable(String)]
        ).returns(T::Array[IPropertyDefinition])
      end
      def find_or_create_definitions(namespace, properties)
        ext_def_class = config_extension.external_definition_class
        definitions = T.unsafe(ext_def_class)
          .for_namespace(namespace)
          .order(property_name: :asc)
          .to_a

        # Use definitions and look for properties that don't exist by downcasing definition.property_name and
        # properties.keys and comparing the sets to find property names that need to be created.
        existing_names = definitions.map { |d| d.property_name.downcase }.to_set
        # Ignore any properties with blank values as that signals we are deleting the value
        # Validation will fail if the definition doesn't exist
        property_names_to_create = properties.keys.reject { |name| existing_names.include?(name.downcase) || properties[name].blank? }

        raise_if_too_many_definitions!(definitions.length + property_names_to_create.length)

        # batch create new definitions
        new_definitions = property_names_to_create.map do |name|
          ext_def_class.create!(
            namespace: namespace,
            property_name: name
          )
        end

        definitions.concat(new_definitions)

        GitHub::PrefillAssociations.prefill_associations(definitions, :namespace, available_records: [namespace])

        definitions
      end

      sig { params(definitions: T::Array[IPropertyDefinition]).void }
      def cleanup_orphaned_definitions(definitions)
        return if definitions.empty?

        # Clean up orphaned definitions that no longer have any value rows.
        # Uses delete_all for an atomic operation that ensures no race between this and a concurrent value
        # creation, then fires instrumentation only for definitions that were actually deleted.
        definition_ids = definitions.map(&:id)
        deleted_count = T.unsafe(config_extension.external_definition_class)
          .where(id: definition_ids)
          .where.not(
            id: T.unsafe(config_extension.external_value_class)
              .where(definition_id: definition_ids)
              .select(:definition_id)
          )
          .delete_all

        if deleted_count > 0
          # Determine which definitions were actually deleted by checking which no longer exist
          surviving_ids = T.unsafe(config_extension.external_definition_class)
            .where(id: definition_ids.to_a)
            .pluck(:id)
            .to_set

          definitions
            .select { |d| definition_ids.include?(d.id) && !surviving_ids.include?(d.id) }
            .each { |d| d.send(:instrument_destroy) }
        end
      end

      sig { params(definition_number: Integer).void }
      def raise_if_too_many_definitions!(definition_number)
        limit = Public::DEFINITION_LIMIT
        if definition_number > limit
          raise DefinitionLimitReachedError, "Too many unique property names in use for this GitHub App installation. Definitions are limited to #{limit} per app installation."
        end
      end

      sig { params(source: CustomPropertiesCore::IPropertySource).returns(T::Boolean) }
      def external_properties_dynamic_naming_enabled?(source)
        if source.is_a?(Orgs::IOrganization)
          FeatureFlag.vexi.enabled?(:external_properties_dynamic_naming, source, source.business, default: false)
        else
          FeatureFlag.vexi.enabled?(:external_properties_dynamic_naming, source, default: false)
        end
      end
    end
  end
end
