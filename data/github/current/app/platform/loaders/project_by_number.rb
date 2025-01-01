# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class ProjectByNumber < Platform::Loader
      def self.load(owner, number)
        self.for(owner).load(number)
      end

      def self.load_all(owner, numbers)
        loader = self.for(owner)
        Promise.all(numbers.map { |number| loader.load(number) })
      end

      def initialize(owner)
        @owner = owner
      end

      def fetch(numbers)
        ::Project.where({
          owner_id: @owner.id,
          owner_type: @owner.class.name,
          number: numbers,
        }).index_by(&:number)
      end
    end
  end
end
