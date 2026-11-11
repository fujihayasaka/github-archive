# typed: true
# frozen_string_literal: true

module Platform
  module Errors
    class ResourceLimitsExceeded < GraphQL::ExecutionError
      attr_reader :message

      MESSAGE = "Resource limits for this query exceeded."
      TYPE = "RESOURCE_LIMITS_EXCEEDED"

      def initialize(message = nil, *args, **options)
        @message = message || MESSAGE
        if args.none? && options.none?
          super
        else
          super(*T.unsafe(args), **T.unsafe(options))
        end
      end

      def to_h
        extra_attrs = {
          "type" => TYPE,
          "message" => @message,
        }
        super.merge(extra_attrs)
      end
    end
  end
end
