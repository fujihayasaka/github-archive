# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class Manifest < Platform::Loader
      include GitHub::Tracing

      def self.load(repository_id, manifest_id, preview: false)
        self.for(repository_id, preview: preview).load(manifest_id)
      end

      def initialize(repository_id, preview: false)
        @repository_id = repository_id
        @preview = preview
      end

      trace_method :fetch
      def fetch(manifest_ids)
        repository = ::Repository.includes(:owner, :network).find(@repository_id)

        # Make sure we have dependency graph enabled
        if !repository.dependency_graph_enabled?
          raise Platform::Errors::Unprocessable, "Dependency graph not enabled for repository"
        end

        include_internal_snapshots = DependencyGraph.include_internal_snapshots?(repository)
        manifest_ids.map do |manifest_id|
          # The manifests query returns an array, we want either the first and only value or nil
          manifest = ::DependencyGraph::ManifestsQuery.new(
            manifest_filter: {
              repository_id: @repository_id,
              manifest_id: manifest_id,
              include_internal_snapshots: include_internal_snapshots,
              preview: @preview,
            },
            include_dependencies: :count
          ).results.value![:manifests]&.first

          [manifest_id, manifest]
        end.to_h
      end
    end
  end
end
