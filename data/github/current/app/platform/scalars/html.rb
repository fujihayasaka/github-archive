# typed: true
# frozen_string_literal: true

module Platform
  module Scalars
    class HTML < Platform::Scalars::Base
      description "A string containing HTML code."

      def self.coerce_input(value, context)
        value.html_safe # rubocop:disable Rails/OutputSafety
      end

      def self.coerce_result(value, context)
        if value.html_safe?
          value
        else
          raise Platform::Errors::Type, "Refusing to coerce non-HTML-safe string to HTML type in GraphQL result"
        end
      end
    end
  end
end
