# typed: strict
# frozen_string_literal: true

module GitHub
  module RemoteCache
    module Compressor
      extend T::Helpers
      interface!

      sig { abstract.params(value: T.untyped).returns(String) }
      def compress(value); end

      sig { abstract.params(raw_value: String).returns(T.untyped) }
      def decompress(raw_value); end
    end
  end
end
