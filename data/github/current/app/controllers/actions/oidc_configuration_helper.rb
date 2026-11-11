# typed: true
# frozen_string_literal: true

module Actions::OIDCConfigurationHelper
  extend self

  include OIDC::RepoCustomPropertyInclusionHelper

  MAX_ITEMS = 100
  PAGE = 1

  CustomPropertyItem = T.type_alias do
    {
      id: Integer,
      propertyName: String,
      inclusionSource: T.nilable(String)
    }
  end

  CustomPropertySearchResult = T.type_alias do
    {
      items: T::Array[CustomPropertyItem],
      totalCount: Integer
    }
  end

  sig { params(source: T.any(Organization, Business)).returns(T::Array[CustomPropertyItem]) }
  def get_included_repo_properties(source)
    definitions = Repositories.domain.custom_properties.get_definitions(source)
    definitions_map = definitions.index_by(&:property_name)

    property_inclusions = list_effective_repo_property_inclusions_for_source(source)
    included_properties = property_inclusions.filter_map do |inclusion|
      definition = definitions_map[inclusion.custom_property_name]
      next unless definition

      { **custom_property_payload(definition), inclusionSource: inclusion.source_type }
    end

    included_properties
  end

  sig { params(source: T.any(Organization, Business), q: T.nilable(String)).returns(CustomPropertySearchResult) }
  def search_repo_custom_properties(source, q = nil)
    # If the source is an enterprise, we want to limit the search to properties that are at that source level.
    # By default, the search will include properties that are managed by any organizations within that enterprise.
    q = "#{q} managed-by:enterprise".strip if source.is_a?(Business)

    results = Repositories.domain.custom_properties.search_definitions(source, q, PAGE, per_page: MAX_ITEMS)
    definitions = T.must(results[:items])

    # If the source is an organization, we want to know if any of the properties are already included at the enterprise level, as that would be the effective setting for that property.
    # No need to fetch inclusions for enterprise source as only enterprise properties are returned.
    business = source.business if source.is_a?(Organization)
    enterprise_inclusions = business.present? ? list_repo_property_inclusions_for_source(business).index_by(&:custom_property_name) : {}

    resolved_properties = definitions.map do |definition|
      { **custom_property_payload(definition), inclusionSource: enterprise_inclusions[definition.property_name]&.source_type }
    end

    { items: resolved_properties, totalCount: results[:total_entries] }
  end

  sig { params(source: T.any(Organization, Business), new_property_names: T::Array[String]).void }
  def update_included_repo_properties(source, new_property_names)
    current_inclusions = list_effective_repo_property_inclusions_for_source(source)
    current_included_property_names = current_inclusions.pluck(:custom_property_name).to_set

    unique_property_names = new_property_names.to_set
    properties_to_add = unique_property_names - current_included_property_names
    properties_to_remove = current_included_property_names - unique_property_names

    net_change = properties_to_add.size - properties_to_remove.size
    validate_repo_inclusion_limit_not_exceeded!(source, net_change) if net_change > 0

    ApplicationRecord::Domain::OidcSetting.transaction do
      delete_repo_property_inclusions_for_source!(source, properties_to_remove.to_a) unless properties_to_remove.empty?

      properties_to_add.each do |property_name|
        validate_repo_property_definition_exists!(source, property_name)
        create_repo_property_inclusion_for_source!(source, property_name)
      end
    end

    # Instrument after successful transaction
    properties_to_add.each { |property_name| instrument_inclusion_event(:created, source, property_name) }
    properties_to_remove.each { |property_name| instrument_inclusion_event(:deleted, source, property_name) }
  end

  private

  def custom_property_payload(definition)
    {
      id: definition.id,
      propertyName: definition.property_name,
    }
  end
end
