# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    module ProjectV2FieldAccessFilter
      def async_can_access?(permission, object)
        return false unless column = object[:field]
        Platform::Helpers::ProjectV2.async_api_can_access?(permission, column)
      end
    end
  end
end
