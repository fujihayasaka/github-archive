# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    # Utility class to generate Hydro envelopes for messages, which can be
    # included in dead-letter messages
    class EnvelopeGenerator
      # Protected: Generates the data for a Hydro envelope for a given message
      #
      # message - A Hydro::Source::Message for which an envelope is desired
      #
      # Returns Hash
      def generate(message)
        message_hash = message.value.transform_values { |value| transform_message_value(value) }

        encoded_envelope = GitHub.hydro_encoder.encode(message_hash, schema: message.schema)
        envelope_hash = Hydro::Schemas::Hydro::V1::Envelope.decode(encoded_envelope).to_h
        envelope_hash[:timestamp] = message.timestamp

        envelope_hash
      end

      # Public: Transform message values so that they can be encoded by Hydro
      #
      # Primarily, this focuses on transforming times represented by hashes into
      # Time objects. For example, a decoded Hydro message may include a time
      # represented by the following Hash:
      #
      #   {:seconds=>1544400617, :nanos=>0}
      #
      # But this value cannot be serialized as is. First, we need to transform it
      # into a Time object.
      #
      # value - The value to transform
      #
      # Returns Object the transformed value, which could be of any type
      def transform_message_value(value)
        if value.is_a?(Hash)
          if value.key?(:seconds)
            Time.at(value[:seconds], value[:nanos], :nanosecond)
          else
            value.transform_values { |v| transform_message_value(v) }
          end
        else
          value
        end
      end
    end
  end
end
