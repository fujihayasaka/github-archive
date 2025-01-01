# typed: strict
# frozen_string_literal: true

module GitHub
  module JSON
    # Wrapper around an arbitrarily structured JSON document, providing a safe way to traverse its contents.
    #
    # Example:
    #
    #  doc0 = GitHub::JSON::ResponseDocument.new({ "outer" => { "key" => "value" } })
    #  doc0.get_string("outer", "key") # => "baz"
    #  doc0.get_string("nope", "nuh-uh", "no") # => nil
    #  doc0.get_string("nope", "nah", fallback: "") #=> ""
    #
    #  doc1 = GitHub::JSON::ResponseDocument.new({ "things" => [{ "inner" => "value"}] })
    #  things = doc1.get_array("things")
    #  things.map { |thing| thing.get_string("inner") } # => ["value"]
    #  doc1.get_array("missing") # => []
    #
    class ArbitraryDocument
      # Return a wrapper around an empty document, which will return fallback values for everything.
      sig { returns(ArbitraryDocument) }
      def self.empty
        @empty ||= T.let(new(nil), T.nilable(ArbitraryDocument))
      end

      # Access a string value at the given path, or return the fallback value if the path is not present.
      sig { params(path: String, fallback: T.nilable(String)).returns(T.nilable(String)) }
      def get_string(*path, fallback: nil)
        at_path_or(fallback, String, path)
      end

      # Construct a new wrapper around a parsed JSON document.
      sig { params(root: T.untyped).void }
      def initialize(root)
        @root = root
      end

      # Access an array of subdocuments at the given path, or return an empty array if the path is not present.
      sig { params(path: String).returns(T::Array[ArbitraryDocument]) }
      def get_array(*path)
        at_path_or([], Array, path).map { |node| ArbitraryDocument.new(node) }
      end

      private

      # Safely traverse an unknown JSON document, returning the fallback value if any step of the path is not present,
      # or has an unexpected class.
      sig { params(fallback: T.untyped, klass: T::Class[T.anything], path: T::Array[String]) .returns(T.untyped) }
      def at_path_or(fallback, klass, path)
        destination_node = path.inject(@root) do |json_node, key|
          next nil unless json_node.is_a?(Hash)
          json_node[key]
        end
        destination_node.is_a?(klass) ? destination_node : fallback
      end
    end
  end
end
