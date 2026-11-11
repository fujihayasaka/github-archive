# typed: strict
# frozen_string_literal: true

module Events
  class Domain
    class Tier1EventAttributesDecoder
      sig { params(attributes_class: T.untyped, attributes_data: T.untyped).void }
      def initialize(attributes_class, attributes_data)
        @attributes = T.let(attributes_class.decode(attributes_data), T.untyped)
      end

      sig { params(event_class: T.class_of(Hook::Event)).returns(T::Hash[Symbol, T.untyped]) }
      def decode(event_class)
        # Extract all attributes from the protobuf model and unwrap wrapper types
        attributes = {}
        @attributes.class.descriptor.each do |field|
          field_value = extract_field_value(@attributes, field)
          attribute_key = field.name.to_sym
          attributes[attribute_key] = field_value if !field_value.nil? && event_class.valid_attribute_keys.include?(attribute_key)
        end
        attributes
      end

      private

      sig { params(attachment_model: T.untyped, field: T.untyped).returns(T.untyped) }
      def extract_field_value(attachment_model, field)
        return nil unless attachment_model.respond_to?(field.name)

        raw_value = attachment_model.send(field.name) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
        return nil if raw_value.nil?

        if field.type == :message
          unwrap_message_value(raw_value, field.subtype.msgclass)
        else
          raw_value
        end
      end

      sig { params(value: T.untyped, message_type: T.untyped).returns(T.untyped) }
      def unwrap_message_value(value, message_type)
        if message_type == Google::Protobuf::Timestamp
          Time.at(value.seconds, value.nanos / 1000.0)
        elsif value.respond_to?(:value)
          value.value
        else
          value.to_h
        end
      end
    end
  end
end
