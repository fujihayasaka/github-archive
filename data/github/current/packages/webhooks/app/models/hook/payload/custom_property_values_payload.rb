# typed: true
# frozen_string_literal: true

class Hook::Payload::CustomPropertyValuesPayload < Hook::Payload

  def to_payload_hash
    {
      action: "updated",
      new_property_values: Api::Serializer.serialize(:custom_properties_value_hash, hook_event.new_property_values),
      old_property_values: Api::Serializer.serialize(:custom_properties_value_hash, hook_event.old_property_values),
    }
  end
end
