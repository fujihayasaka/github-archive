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
        statuses = ::Statuses.domain.current_statuses_for_shas_group_by(repository_id: @repository.id, shas: oids, group_by: ::Statuses::Domain::GroupByField::SHA)

        statuses.default = [].freeze

        statuses
      end
    end
  end
end
