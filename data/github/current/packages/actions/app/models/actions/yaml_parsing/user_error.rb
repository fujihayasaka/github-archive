# typed: true
# frozen_string_literal: true

module Actions
  module YamlParsing
    # Common error type for all YAML parsing errors
    class UserError < StandardError
      def initialize(message)
        super(message)
      end
    end
  end
end
