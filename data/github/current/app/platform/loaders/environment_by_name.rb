# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class EnvironmentByName < Platform::Loader
      def self.load(repository_id, name)
        self.for(repository_id).load(name.downcase)
      end

      def self.load_all(repository_id, names)
        loader = self.for(repository_id)
        Promise.all(names.map { |name| loader.load(name.downcase) })
      end

      def initialize(repository_id)
        @repository_id = repository_id
      end

      def fetch(names)
        ::Environment.where(repository_id: @repository_id, name: names).index_by { |env| env.name.downcase }
      end
    end
  end
end
