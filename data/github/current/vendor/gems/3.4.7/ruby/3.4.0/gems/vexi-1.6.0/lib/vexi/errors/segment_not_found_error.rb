# frozen_string_literal: true
#              

module Vexi
  module Errors
    # Public: Vexi segment not found error.
    class SegmentNotFoundError < EntityNotFoundError
      def initialize(entity_id)
        super(entity_id, "segment")
      end
    end
  end
end
