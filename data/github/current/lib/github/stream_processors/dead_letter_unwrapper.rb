# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module DeadLetterUnwrapper
      sig { params(consumer_message: Hydro::Consumer::ConsumerMessage).returns(Hydro::Consumer::ConsumerMessage) }
      def self.unwrap(consumer_message)
        schema_type_url = consumer_message.value.dig(:envelope, :type_url)
        schema = schema_type_url.sub(Hydro::TYPE_URL_PREFIX.to_s, "")
        descriptor_pool = Google::Protobuf::DescriptorPool.generated_pool
        schema_class = Hydro::Protobuf.get_schema_class(schema, descriptor_pool)
        envelope_generator = EnvelopeGenerator.new
        payload = schema_class.decode(consumer_message.value.dig(:envelope, :message)).to_h.transform_values do |value|
          envelope_generator.transform_message_value(value)
        end

        encoded = GitHub.hydro_encoder.encode(
          payload.to_h,
          schema: schema,
          timestamp: Time.at(*consumer_message.value.dig(:envelope, :timestamp).values),
        )
        decoded = Hydro::Decoding::ProtobufDecoder.decode(encoded)
        Hydro::Consumer::ConsumerMessage.new(
          id: decoded.id,
          value: decoded.message,
          source_message: consumer_message.source_message,
          timestamp: decoded.timestamp,
          schema: decoded.schema,
        )
      end
    end
  end
end
