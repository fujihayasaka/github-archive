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

  # Creates a Hash to be serialized to JSON.
  #
  # definition - PropertyDefinition instance
  # options    - Hash
  #
  # Returns a Hash if the custom property definition exists, or nil.
  def property_definition_hash(definition, options = {})
    return unless definition

    options = Api::SerializerOptions.from(options)

    definition_url = if base_path = BASE_PATH[definition.source_type]
      encode_property_name = ERB::Util.url_encode(definition.property_name)
      url("#{base_path}/#{definition.source.to_param}/properties/schema/#{encode_property_name}", options)
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
