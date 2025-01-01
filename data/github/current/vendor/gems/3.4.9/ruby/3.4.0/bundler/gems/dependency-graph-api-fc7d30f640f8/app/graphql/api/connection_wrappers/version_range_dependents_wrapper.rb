module API
  module ConnectionWrappers
    class VersionRangeDependentsWrapper < Delegator
      def self.encode(unencoded_data, *)
        API::Schema.cursor_encoder.encode(MessagePack.pack(unencoded_data))
      end

      def self.decode(encoded_text, *)
        MessagePack.unpack(API::Schema.cursor_encoder.decode(encoded_text))
      rescue MessagePack::MalformedFormatError
        raise GraphQL::ExecutionError, "Invalid cursor: #{encoded_text.inspect}"
      end

      def encode(*args)
        self.class.encode(*args)
      end

      def decode(*args)
        self.class.decode(*args)
      end

      def cursor_from_node(node)
        encode(node.to_cursor)
      end

      def offset_from_cursor(cursor)
        decode(cursor)
      end
    end
  end
end
