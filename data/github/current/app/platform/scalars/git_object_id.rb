# typed: true
# frozen_string_literal: true

module Platform
  module Scalars
    class GitObjectID < Platform::Scalars::Base
      description "A Git object ID."

      def self.coerce_input(value, context)
        normalized_value = value&.downcase

        if normalized_value&.match?(GitHub::HashAlgorithm::FULL_OID_STANDALONE_REGEXP) # support SHA-1 and SHA-256
          normalized_value
        else
          # TODO: raise?
          nil
        end
      end

      def self.coerce_result(value, context)
        value
      end
    end
  end
end
