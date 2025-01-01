# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class PushByRepository < Platform::Loader
      include Repositories::Domain::Provider

      def self.load(repository_id, push_id)
        self.for(repository_id).load(push_id)
      end

      def initialize(repository_id)
        @repository_id = repository_id
      end

      def fetch(push_ids)
        repositories_domain.pushes.by_repository_id(push_ids: push_ids, repository_id: @repository_id).index_by(&:id)
      end
    end
  end
end
