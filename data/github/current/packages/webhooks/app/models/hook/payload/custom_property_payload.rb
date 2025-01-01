# typed: true
# frozen_string_literal: true

class Hook::Payload::CustomPropertyPayload < Hook::Payload

  def to_payload_hash
    property = if hook_event.definition.nil?
      { property_name: hook_event.property_name }
    else
      Api::Serializer.serialize(:property_definition_hash, hook_event.definition)
    end

    {
      action: hook_event.action,
      definition: property,
    }
  end

end
