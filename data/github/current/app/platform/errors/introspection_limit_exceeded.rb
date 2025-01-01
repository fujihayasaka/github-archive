# typed: true
# frozen_string_literal: true

module Platform
  module Errors
    class IntrospectionLimitExceeded < Errors::Analysis
      MESSAGE_TEMPLATE = "Introspection fields may only be used %{limit} times, but some fields were used more than that: %{fields}"
      def initialize(usages, limit)
        message = MESSAGE_TEMPLATE % {
          limit: limit,
          fields: usages.map { |name, count| "#{name} (#{count})" }.join(", "),
        }
        super("INTROSPECTION_LIMIT_EXCEEDED", message)
      end
    end
  end
end
