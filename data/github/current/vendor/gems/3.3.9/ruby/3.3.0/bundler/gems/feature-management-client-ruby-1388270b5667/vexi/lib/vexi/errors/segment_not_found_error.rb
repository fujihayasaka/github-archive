# frozen_string_literal: true
# typed: strict

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
