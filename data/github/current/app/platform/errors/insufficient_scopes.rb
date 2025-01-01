# typed: true
# frozen_string_literal: true

module Platform
  module Errors
    class InsufficientScopes < Errors::Analysis
      attr_reader :type

      def initialize(*args, **options)
        T.unsafe(Errors::Analysis.instance_method(:initialize)).bind(self).call("INSUFFICIENT_SCOPES", *args, **options)
      end

      def to_h
        super.merge({
          "type" => type,
        })
      end
    end
  end
end
