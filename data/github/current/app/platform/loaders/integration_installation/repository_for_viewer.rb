# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    module IntegrationInstallation
      class RepositoryForViewer < Platform::Loader
        def self.load(repository, viewer)
          self.for(viewer).load(repository)
        end

        def initialize(viewer)
          @viewer = viewer
        end

        def fetch(repositories)
          repository_ids = repositories.map(&:id)
          for_user = ::IntegrationInstallation.with_user(viewer, repository_ids: repository_ids)
          repositories.map { |repository| [repository, for_user.with_repository(repository)] }.to_h
        end

        private

        attr_reader :viewer
      end
    end
  end
end
