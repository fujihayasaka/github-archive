# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module Fastly
      include Kernel
      # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
      def fastly
        @fastly ||= if fastly_enabled?
          require "fastly"
          ::Fastly.new
        end
      end
      # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

      def fastly_enabled?
        fastly_api_token.present?
      end

      attr_accessor :fastly_api_token
      attr_accessor :fastly_private_key_id
    end
  end

  extend Config::Fastly
end
