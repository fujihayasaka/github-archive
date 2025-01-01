# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    module IntegrationInstallation
      class Repository < Platform::Loader
        def self.load(repository, integration_id)
          self.for(repository).load(integration_id)
        end

        def initialize(repository)
          @repository = repository
        end

        def fetch(integration_ids)
          ::IntegrationInstallation.
            with_repository(repository).
            where(integration_id: integration_ids).
            index_by(&:integration_id)
        end

        private

        attr_reader :repository
      end
    end
  end
end
