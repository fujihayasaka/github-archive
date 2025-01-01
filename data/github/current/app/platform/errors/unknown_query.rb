# typed: true
# frozen_string_literal: true

module Platform
  module Errors
    class UnknownQuery < Errors::Internal
      sig { params(query_id: String).void }
      def initialize(query_id)
        super("Unknown Query id #{query_id}")
      end
    end
  end
end
