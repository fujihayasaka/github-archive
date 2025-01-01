# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class Statuses < Platform::Loader
      def self.load(repository, oid)
        self.for(repository).load(oid)
      end

      def initialize(repository)
        @repository = repository
      end

      def fetch(oids)
        statuses = ::Statuses::Service.current_for_shas(repository_id: @repository.id, shas: oids).group_by(&:sha)

        statuses.default = [].freeze

        statuses
      end
    end
  end
end
