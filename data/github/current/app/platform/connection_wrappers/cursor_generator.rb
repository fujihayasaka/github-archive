# typed: true
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    module CursorGenerator
      CURSOR_IDENTIFIER = "cursor:"
      V2_PREFIX = "v2:"

      # Encode arbitrary data into an opaque cursor for resuming pagination.
      # See:
      # - https://facebook.github.io/relay/graphql/connections.htm#sec-Cursor
      # - http://graphql.org/learn/pagination/#pagination-and-edges
      #
      # - data: The String to encode into a cursor, or an Array of values to serialize
      # - version: How to stringify `data`
      #
      # Returns an opaque String which clients can use to continue paginating.
      sig do
        params(
          data: T.anything,
          version: Symbol
        ).returns(String)
      end
      def self.generate_cursor(data, version: :v1)
        case version
        when :v2
          serialized_data = MessagePack.pack(data)
          Base64.urlsafe_encode64("#{CURSOR_IDENTIFIER}#{V2_PREFIX}#{serialized_data}")
        when :v1
          Base64.strict_encode64("#{CURSOR_IDENTIFIER}#{data}")
        else
          raise ArgumentError, "Unexpected generate_cursor version: #{version}" # rubocop:disable GitHub/UsePlatformErrors
        end
      end

      sig { params(item: String).returns(String) }
      def self.safe_urlsafe_decode64(item)
        Base64.urlsafe_decode64(item)
      rescue ArgumentError => err
        # urlsafe_decode64 raises an error instead of returning nonsense,
        # so rescue that error and raise our normal error
        if err.message == "invalid base64"
          raise Errors::Cursor.new(item)
        else
          raise err # rubocop:disable GitHub/UsePlatformErrors
        end
      end

      # Given a client-provided cursor, extract the original data in it.
      #
      # - item: The String cursor which client got from us and provided back to continue
      #
      # Returns whatever was provided to `generate_cursor` ...
      # _or_ whatever the user put into a reverse-engineered cursor.
      sig { params(item: T.untyped).returns(T.untyped) }
      def self.resolve_cursor(item)
        decoded = CursorGenerator.safe_urlsafe_decode64(item.to_s)

        if !decoded.starts_with?(CURSOR_IDENTIFIER)
          raise Errors::Cursor.new(item)
        end

        versioned_data = decoded[CURSOR_IDENTIFIER.length..-1]

        parsed_data = case T.must(versioned_data)[0..2]
        when V2_PREFIX
          cursor_data = T.must(versioned_data)[V2_PREFIX.length..-1]
          begin
            MessagePack.unpack(cursor_data)
          rescue EOFError
            raise Errors::Cursor.new(item)
          end
        else
          # V1 doesn't have a prefix
          # and isn't serialized in any special way
          versioned_data
        end
      end
    end
  end
end
