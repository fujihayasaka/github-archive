# typed: true
# frozen_string_literal: true

module Platform
  module Errors
    class Analysis < GraphQL::AnalysisError
      attr_reader :type

      def initialize(type, *args, **options)
        @type = type.upcase
        super(*T.unsafe(args), **T.unsafe(options))
      end

      def to_h
        super.merge({
          "type" => type,
        })
      end
    end
  end
end
