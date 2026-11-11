# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class ExpandedGitCommitOid < Platform::Loader
      def self.load(repository, sha)
        repository.async_network.then do
          self.for(repository).load(sha)
        end
      end

      def self.load_all(repository, shas)
        repository.async_network.then do
          loader = self.for(repository)
          Promise.all(shas.map { |sha| loader.load(sha) })
        end
      end

      def initialize(repository)
        @repository = repository
      end

      def fetch(oids)
        oid_map = {}
        oids.each_slice(SpokesAPI::Client::RESOLVE_OBJECT_BATCH_SIZE).each do |batch|
          selectors = batch.map do |oid|
            {
              by_name: { name: oid },
              object_type: { type: :TYPE_COMMIT }
            }
          end

          objects = @repository.spokes_api.resolve_objects_by(selectors)
          batch.zip(objects.items).each do |oid, resolved|
            # ensure resolved OID starts with the provided short OID (case insensitive),
            # to validate this is a commit reference & not a branch
            if resolved.error.empty? && resolved.object.oid.id.start_with?(oid.downcase)
              oid_map[oid] = resolved.object.oid.id
            end
          end
        end

        oid_map
      end
    end
  end
end
