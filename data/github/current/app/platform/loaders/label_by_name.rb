# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class LabelByName < Platform::Loader
      def self.load(repository_id, name)
        self.for(repository_id).load(name)
      end

      def initialize(repository_id)
        @repository_id = repository_id
      end

      def fetch(names)
        ::Label.where(repository_id: @repository_id, name: names).index_by(&:name)
      end
    end
  end
end
