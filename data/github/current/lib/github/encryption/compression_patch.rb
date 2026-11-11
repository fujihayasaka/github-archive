# typed: true
# frozen_string_literal: true

module GitHub
  module Encryption
    module CompressionPatch
      def compress_if_worth_it(string)
        [string, false]
      end
    end
  end
end
