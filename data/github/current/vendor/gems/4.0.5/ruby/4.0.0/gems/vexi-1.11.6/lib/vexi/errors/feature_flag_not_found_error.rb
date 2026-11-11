# frozen_string_literal: true
#              

module Vexi
  module Errors
    # Public: Vexi feature flag not found error.
    class FeatureFlagNotFoundError < EntityNotFoundError
      def initialize(entity_id)
        super(entity_id, "feature flag")
      end
    end
  end
end
