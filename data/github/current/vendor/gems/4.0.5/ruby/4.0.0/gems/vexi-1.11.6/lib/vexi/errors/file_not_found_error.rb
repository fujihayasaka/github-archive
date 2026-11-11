# frozen_string_literal: true
#              

module Vexi
  module Errors
    # Public: Vexi file not found error.
    class FileNotFoundError < EntityNotFoundError
      def initialize(entity_id)
        super(entity_id, "file")
      end
    end
  end
end
