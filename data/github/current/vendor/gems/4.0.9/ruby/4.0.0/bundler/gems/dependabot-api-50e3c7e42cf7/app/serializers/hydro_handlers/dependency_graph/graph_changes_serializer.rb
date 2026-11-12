# frozen_string_literal: true

module HydroHandlers
  module DependencyGraph
    class GraphChangesSerializer < ActiveJob::Serializers::ObjectSerializer
      def serialize?(argument)
        argument.is_a?(::HydroHandlers::DependencyGraph::GraphChanges)
      end

      def serialize(graph_changes)
        # Serialize the raw changes array with ecosystem symbols and directories
        changes = []
        graph_changes.each do |change|
          # Find the ecosystem symbol from the package manager
          ecosystem = ::HydroHandlers::DependencyGraph::GraphChanges::ECOSYSTEMS.key(change.package_manager)
          changes << {
            ecosystem: ecosystem,
            directory: change.directory,
          }
        end

        super(graph_changes: changes)
      end

      def deserialize(hash)
        ::HydroHandlers::DependencyGraph::GraphChanges.from_active_job(hash)
      end
    end
  end
end
