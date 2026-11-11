# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class LfsRepositories < Platform::Loader
      def self.load(owner_id)
        self.for.load(owner_id)
      end

      def fetch(owner_ids)
        owner_id_by_source_id = {}

        repository_scope = ::Repository.where(parent_id: nil, active: true, locked: false).where(owner_id: owner_ids)
        owner_id_by_source_id = repository_scope.pluck(:source_id, :owner_id).to_h

        media_blob_scope = ::Media::Blob.verified.distinct
        repository_network_ids = owner_id_by_source_id.keys.each_slice(10000).flat_map do |source_ids|
          media_blob_scope.where(repository_network_id: source_ids).pluck(:repository_network_id)
        end

        repositories = repository_network_ids.each_slice(10000).flat_map do |network_ids|
          repository_scope.where(source_id: network_ids)
        end

        results = repositories.group_by(&:owner_id)
        results.default = [].freeze
        results
      end
    end
  end
end
