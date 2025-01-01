# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class SortBy < Platform::Objects::Base
      description "Represents a sort by field and direction."

      scopeless_tokens_as_minimum

      def self.async_api_can_access?(permission, object)
        async_can_access?(permission, object)
      end

      def self.async_viewer_can_see?(permission, object)
        async_can_access?(permission, object)
      end

      def self.async_can_access?(permission, object)
        Platform::Loaders::ActiveRecord.load(MemexProjectColumn, object[:field]).then do |column|
          next false if column.nil?

          Platform::Helpers::ProjectV2.async_api_can_access?(permission, column)
        end
      end
      private_class_method :async_can_access?

      field :field, Integer, description: "The id of the field by which the column is sorted.", null: false
      field :direction, Platform::Enums::OrderDirection, description: "The direction of the sorting. Possible values are ASC and DESC.", null: false
    end
  end
end
