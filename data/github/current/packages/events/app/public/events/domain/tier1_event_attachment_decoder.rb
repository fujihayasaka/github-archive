
# typed: strict
# frozen_string_literal: true

module Events
  class Domain
    class Tier1EventAttachmentDecoder
      sig { params(attachment_class: T.untyped, attachment_data: T.untyped).void }
      def initialize(attachment_class, attachment_data)
        @attachment = T.let(attachment_class.decode(attachment_data), T.untyped)
      end

      sig { params(field_name: Symbol, model_class: T.class_of(ActiveRecord::Base)).returns(T.nilable(ActiveRecord::Base)) }
      def decode(field_name, model_class)
        raise ArgumentError, "Attachment does not respond to #{field_name}" unless @attachment.respond_to?(field_name)
        attachment_model = @attachment.send(field_name) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
        return nil if attachment_model.nil?

        # Extract all attributes from the protobuf model and unwrap wrapper types
        attributes = {}
        attachment_model.class.descriptor.each do |field|
          field_value = extract_field_value(model_class, attachment_model, field)
          attributes[field.name] = field_value unless field_value.nil?
        end

        attributes = filter_attributes(attributes, model_class)
        model_class.new(attributes)
      end

      private

      sig { params(attributes: T.untyped, model_class: T.class_of(ActiveRecord::Base)).returns(T.untyped) }
      def filter_attributes(attributes, model_class)
        valid_keys = model_class.column_names
        attributes.filter do |key|
          valid_keys.any? { |valid_key| key.to_s == valid_key }
        end
      end

      sig { params(model_class: T.untyped, attachment_model: T.untyped, field: T.untyped).returns(T.untyped) }
      def extract_field_value(model_class, attachment_model, field)
        return nil unless attachment_model.respond_to?(field.name)

        raw_value = attachment_model.send(field.name) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
        return nil if raw_value.nil?
        decoded_value = raw_value

        raw_value = unwrap_message_value(raw_value, field.subtype.msgclass) if field.type == :message

        if serialized_attribute?(model_class, field.name)
          model_class.type_for_attribute(field.name).coder.load(raw_value)
        else
          raw_value
        end
      end

      sig { params(value: T.untyped, message_type: T.untyped).returns(T.untyped) }
      def unwrap_message_value(value, message_type)
        if message_type == Google::Protobuf::Timestamp
          Time.at(value.seconds, value.nanos / 1000.0)
        else
          value.value
        end
      end

      sig { params(model: T.untyped, attr_name: String).returns(T::Boolean) }
      def serialized_attribute?(model, attr_name)
        model.attribute_types[attr_name.to_s].is_a?(ActiveRecord::Type::Serialized)
      end
    end
  end
end
