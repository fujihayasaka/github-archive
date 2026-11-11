# typed: strict
# frozen_string_literal: true

module Mobile
  module Copilot
    module Paywall
      module Errors
        class UnknownFeatureTypeError < StandardError
          sig { returns(String) }
          attr_reader :feature_type

          sig { params(feature_type: String).void }
          def initialize(feature_type)
            @feature_type = feature_type
            super("Unknown feature type: #{feature_type}")
          end
        end
      end
    end
  end
end
