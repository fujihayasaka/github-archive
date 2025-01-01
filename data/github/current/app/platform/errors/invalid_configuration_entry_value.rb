# typed: true
# frozen_string_literal: true

module Platform
  module Errors
    class InvalidConfigurationEntryValue < Errors::Internal
      def initialize(value, setting_name)
        message = "`#{value}` is an unexpected value for the `#{setting_name}` setting"

        super(message)
      end
    end
  end
end
