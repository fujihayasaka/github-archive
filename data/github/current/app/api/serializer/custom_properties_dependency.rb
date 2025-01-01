# typed: true
# frozen_string_literal: true

module Api::Serializer::CustomPropertiesDependency
  extend T::Helpers
  requires_ancestor { Api::Serializer }

  BASE_PATH = {
    "org" => "/orgs",
    "business" => "/enterprises"
  }.freeze

  SOURCE_TYPE = {
    "org" => "organization",
    "business" => "enterprise"
  }.freeze

  TARGET_PREFIX = {
    org: "org-properties",
    repo: "properties"
  }.freeze

  # Creates a Hash to be serialized to JSON.
  #
  # definition - PropertyDefinition instance
  # options    - Hash
  #
  # Returns a Hash if the custom property definition exists, or nil.
  def property_definition_hash(definition, options = {})
    return unless definition

    common_property_definition_hash(definition, :repo, options)
  end

  # Creates a Hash to be serialized to JSON.
  #
  # definition - PropertyDefinition instance
  # options    - Hash
  #
  # Returns a Hash if the custom property definition exists, or nil.
  def org_property_definition_hash(definition, options = {})
    return unless definition

    common_property_definition_hash(definition, :org, options)
  end

  def custom_properties_value_hash(property_values, options = {})
    return unless property_values

    property_values.map do |property_name, value|
      {
        property_name: property_name,
        value: value
      }
    end
  end

  # Creates a Hash to be serialized to JSON.
  #
  # data - a hash of property values
  # options    - Hash
  #
  # Returns a Hash of organization identification with an array of
  # property names and values
  def org_property_effective_values_hash(data, options = {})
    return unless data

    organization = data[:organization]
    property_values = data[:property_values]

    {
      organization_id: organization.id,
      organization_login: organization.display_login,
      properties: property_values.map do |property_name, value|
        {
          property_name: property_name,
          value: value
        }
      end
    }
  end

  private

  # Creates a Hash to be serialized to JSON.
  #
  # definition - PropertyDefinition instance
  # target     - One of the supported target symbols: `:repo`, `:org`
  # options    - Hash
  #
  # Returns a Hash if the custom property definition exists, or nil.
  def common_property_definition_hash(definition, target, options = {})
    raise ArgumentError, "Unsupported target: '#{target}'" unless TARGET_PREFIX.keys.include?(target)

    options = Api::SerializerOptions.from(options)
    target_prefix = TARGET_PREFIX[target]

    definition_url = if base_path = BASE_PATH[definition.source_type]
      encode_property_name = ERB::Util.url_encode(definition.property_name)
      url("#{base_path}/#{definition.source.to_param}/#{target_prefix}/schema/#{encode_property_name}", options)
    end

    {
      property_name: definition.property_name,
      url: definition_url,
      source_type: SOURCE_TYPE[definition.source_type],
      value_type: definition.value_type,
      required: definition.required,
      default_value: definition.default_value,
      description: definition.description,
      allowed_values: definition.allowed_values,
      values_editable_by: definition.values_editable_by,
    }.compact
  end
end
