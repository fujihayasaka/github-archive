# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class Repository < Connections::Base
      MAX_32_BIT_SIGNED_INT = 2**31 - 1

      description "A list of repositories owned by the subject."

      total_count_field

      field :total_disk_usage, Integer,
        description: "The total size in kilobytes of all repositories in the connection. Value will never be larger than max 32-bit signed integer.",
        null: false

      def total_disk_usage
        disk_usage = case @object.items
        when Repositories::RepositoryCursorCollection
          T.cast(
            @object.items,
            Repositories::RepositoryCursorCollection[Repositories::IRepository]
          ).total_disk_usage
        when Array
          @object.items.sum(&:disk_usage)
        else # ActiveRecord::Relation
          @object.items.sum(:disk_usage)
        end

        disk_usage.clamp(0, MAX_32_BIT_SIGNED_INT)
      end
    end
  end
end
