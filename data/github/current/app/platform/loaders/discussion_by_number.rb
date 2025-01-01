# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class DiscussionByNumber < Platform::Loader
      def self.load(repository_id, number)
        self.for(repository_id).load(number)
      end

      def self.load_all(repository_id, numbers)
        loader = self.for(repository_id)
        Promise.all(numbers.map { |number| loader.load(number) })
      end

      def initialize(repository_id)
        @repository_id = repository_id
      end

      def fetch(numbers)
        ::Discussion.readonly(false).for_repository(@repository_id).
          with_number(filter_invalid_numbers(numbers)).index_by(&:number)
      end

      def filter_invalid_numbers(numbers)
        type = ::Discussion.type_for_attribute("number")
        max = type.send(:max_value)
        min = type.send(:min_value)

        numbers.reject { |n| n >= max || n < min }
      end
    end
  end
end
