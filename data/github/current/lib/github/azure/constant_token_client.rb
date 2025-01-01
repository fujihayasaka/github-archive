# typed: true
# frozen_string_literal: true

module GitHub
  module Azure
    class ConstantTokenClient

      def initialize(token:)
        @token = token
      end

      attr_reader :token
    end
  end
end
