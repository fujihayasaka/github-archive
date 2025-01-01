# typed: true
# frozen_string_literal: true

module Api::Serializer::CustomPropertiesDependency
  # Creates a Hash to be serialized to JSON.
  #
  # definition - PropertyDefinition instance
  # options    - Hash
  #
  # Returns a Hash if the custom property definition exists, or nil.
  def property_definition_hash(definition, options = {})
    return unless definition

    options = Api::SerializerOptions.from(options)

    source = definition.source
    definition_url = if source.is_a?(Organization)
      encode_property_name = ERB::Util.url_encode(definition.property_name)
      "/orgs/#{source.login_for_api(use: options[:serialize_login])}/properties/schema/#{encode_property_name}"
    end

    {
      property_name: definition.property_name,
      url: definition_url,
      value_type: definition.value_type,
      required: definition.required,
      default_value: definition.default_value,
      description: definition.description,
      allowed_values: definition.allowed_values,
      values_editable_by: definition.values_editable_by,
    }.compact
  end
end
