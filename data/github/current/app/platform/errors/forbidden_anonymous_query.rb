# typed: true
# frozen_string_literal: true

module Platform
  module Errors
    class ForbiddenAnonymousQuery < Errors::Internal
      sig { params(query_id: String).void }
      def initialize(query_id)
        super("Forbidden Anonymous Query id #{query_id}")
      end
    end
  end
end
