# typed: strict
# frozen_string_literal: true

module Events
  class Domain
    class Tier1EventAttachmentBuilder
      sig { params(attachment_class: T::untyped).void }
      def initialize(attachment_class)
        @attachment_class = attachment_class
        @models = T.let(nil, T.nilable(T::Hash[Symbol, ActiveRecord::Base]))
      end

      sig { params(field_name: Symbol, model: ActiveRecord::Base).void }
      def model(field_name, model)
        @models ||= {}
        @models[field_name] = model
      end

      sig { returns(T.untyped) }
      def build
        return unless @models

        attachment = @attachment_class.new
        descriptor = @attachment_class.descriptor

        @models.each do |field_name, model|
          process_model(field_name, model, descriptor, attachment)
        end

        attachment
      end

      private

      sig { params(field_name: Symbol, model: ActiveRecord::Base, descriptor: T.untyped, attachment: T.untyped).void }
      def process_model(field_name, model, descriptor, attachment)
        field_descriptor = descriptor.lookup(field_name.to_s)
        raise ArgumentError, "Unknown attachment field: #{field_name}" unless field_descriptor
        raise ArgumentError, "Attachment field #{field_name} is not a message type" unless field_descriptor.type == :message
        model_attachment_class = field_descriptor.subtype.msgclass
        model_attachment_descriptor = model_attachment_class.descriptor
        model_attachment = model_attachment_class.new
        model.attributes.each do |attr_name, attr_value|
          model_attribute(attr_name, attr_value, model, model_attachment, model_attachment_descriptor)
        end
        attachment.send("#{field_name}=", model_attachment)
      end

      sig { params(attr_name: String, attr_value: T.untyped, model: ActiveRecord::Base, model_attachment: T.untyped, model_attachment_descriptor: T.untyped).void }
      def model_attribute(attr_name, attr_value, model, model_attachment, model_attachment_descriptor)
        return unless attr_value
        field_descriptor = model_attachment_descriptor.lookup(attr_name)
        # If the model contains a field not present in the attachment don't set it.
        return unless field_descriptor
        attribute(model, model_attachment, field_descriptor, attr_name)
      end

      sig { params(model: T.untyped, attachment: T.untyped, field_descriptor: T.untyped, attr_name: String).void }
      def attribute(model, attachment, field_descriptor, attr_name)
        return unless attachment.respond_to?("#{attr_name}=")

        begin
          val_to_set = prepare_attribute_value(model, attr_name, field_descriptor)
          attachment.send("#{attr_name}=", val_to_set) unless val_to_set.nil?
        rescue => e
          raise ArgumentError, "Error setting attribute '#{attr_name}': #{e.message}"
        end
      end

      sig { params(model: T.untyped, attr_name: String, field_descriptor: T.untyped).returns(T.untyped) }
      def prepare_attribute_value(model, attr_name, field_descriptor)
        val = model.read_attribute_before_type_cast(attr_name)

        return if val.nil?

        if field_descriptor.type == :message
          message_field(field_descriptor, val)
        else
          val
        end
      end

      sig { params(field_descriptor: T.untyped, val: T.untyped).returns(T.untyped) }
      def message_field(field_descriptor, val)
        message_class = field_descriptor.subtype.msgclass

        if message_class == Google::Protobuf::BytesValue
          bytes_value(val)
        elsif message_class == Google::Protobuf::Timestamp
          timestamp_value(val)
        else
          default_message(message_class, val)
        end
      end

      sig { params(val: T.untyped).returns(Google::Protobuf::BytesValue) }
      def bytes_value(val)
        Google::Protobuf::BytesValue.new(value: val.to_s.b)
      end

      sig { params(val: T.untyped).returns(Google::Protobuf::Timestamp) }
      def timestamp_value(val)
        Google::Protobuf::Timestamp.new(seconds: val.to_i)
      end

      sig { params(message_class: T.untyped, val: T.untyped).returns(T.untyped) }
      def default_message(message_class, val)
        message_class.new(value: val)
      end
    end
  end
end
