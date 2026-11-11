# typed: strict
# frozen_string_literal: true

class ExternalPropertiesDefinitionsManager
  include CustomPropertiesCore
  include CustomPropertiesCore::Errors

  # Public: Initializes a new instance to handle external property definitions for a source.
  #
  # source           - The org or business to handle external property definitions for
  # config_extension - The config extension that provides external definition and value classes
  sig { params(source: PropertySource, config_extension: ExternalProperties::ICustomPropertiesConfigExtension).void }
  def initialize(source, config_extension)
    @source = source
    @source_type = T.let(source.is_a?(::Business) ? :business : :org, Symbol)
    @config_extension = config_extension
  end

  # Public: Returns all external property definitions for the given source.
  #
  # namespace_id - The namespace to scope definitions to (optional; when nil, returns all namespaces)
  #
  # Returns a hash of namespace_id to sorted array of definitions.
  sig { params(namespace_id: T.nilable(Integer)).returns(T::Hash[String, T::Array[IPropertyDefinition]]) }
  def get_definitions(namespace_id = nil)
    namespaces = if namespace_id
      T.unsafe(namespace_class).where(id: namespace_id).to_a
    else
      T.unsafe(namespace_class).for_source(@source).to_a
    end

    definitions = T.unsafe(definition_class)
    .for_namespace_ids([namespaces.map(&:id)])
    .order(property_name: :asc)
    .to_a

    GitHub::PrefillAssociations.prefill_associations(definitions, :namespace, available_records: namespaces)

    # TODO: Handle merging conflicting definitions at org and business levels
    definitions.group_by { |d| d.namespace.display_name }
  end

  # Public: Returns a single external property definition by name, or nil if not found.
  #
  # namespace_id  - The namespace to scope definitions to
  # property_name - The name of the property to look up
  sig { params(namespace_id: Integer, property_name: String).returns(T.nilable(IPropertyDefinition)) }
  def get_definition(namespace_id, property_name)
    T.unsafe(definition_class).for_namespace_ids([namespace_id])
      .to_a.find { |d| d.property_name.downcase == property_name.downcase }
  end

  # Public: Deletes an external property definition and its associated values.
  #
  # namespace_id  - The namespace the definition belongs to
  # property_name - The name of the property to delete
  #
  # Returns the deleted definition, or nil if it was not found.
  sig do
    params(
      namespace_id: Integer,
      property_name: String,
    ).returns(T.nilable(IPropertyDefinition))
  end
  def delete_definition(namespace_id:, property_name:)
    definition = T.unsafe(definition_class).for_namespace_ids([namespace_id])
      .to_a.find { |d| d.property_name.downcase == property_name.downcase }
    definition&.destroy!
    definition
  end

  # Public: Deletes all external property definitions (and their associated values) for the given namespace.
  #
  # namespace_id - The namespace to delete definitions for
  sig { params(namespace_id: Integer).void }
  def destroy_all_definitions(namespace_id)
    T.unsafe(definition_class).for_namespace_ids([namespace_id]).destroy_all
  end

  # Merges org and business definitions, ensuring that business definitions take precedence over org definitions
  # with the same namespace and property name. Definitions in different namespaces are kept independently.
  # Returns a new array of definitions sorted by namespace_id and property name.
  sig { params(business_defs: T::Array[ExternalProperties::DefinitionBase], org_defs: T::Array[ExternalProperties::DefinitionBase]).returns(T::Array[ExternalProperties::DefinitionBase]) }
  def self.merge_definitions(business_defs, org_defs)
    biz_keys = business_defs.map { |defn| [T.unsafe(defn).namespace.display_name, defn.property_name.downcase] }.to_set
    filtered_org_defs = org_defs.reject { |defn| biz_keys.include?([T.unsafe(defn).namespace.display_name, defn.property_name.downcase]) }

    (filtered_org_defs + business_defs).sort_by { |defn| [T.unsafe(defn).namespace.display_name, defn.property_name.downcase] }
  end

  private

  sig { returns(ExternalProperties::ICustomPropertiesConfigExtension::ExternalNamespaceModelImpl) }
  def namespace_class
    @config_extension.external_namespace_class
  end

  sig { returns(ExternalProperties::ICustomPropertiesConfigExtension::ExternalDefinitionModelImpl) }
  def definition_class
    @config_extension.external_definition_class
  end
end
