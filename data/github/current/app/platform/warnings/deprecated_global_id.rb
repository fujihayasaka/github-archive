# typed: true
# frozen_string_literal: true

module Platform
  module Warnings
    class DeprecatedGlobalId
      def initialize(object)
        @message = "The id #{object.legacy_global_id} is deprecated. Update your cache to use the next_global_id from the data payload."
        @data    = { legacy_global_id: object.legacy_global_id, next_global_id: object.next_global_id }
        @link    = "https://docs.github.com" # TODO TBD
      end

      def to_h
        {
          type: Platform::Warnings::DEPRECATION,
          message: @message,
          data: @data,
          link: @link,
        }
      end
    end
  end
end
