# frozen_string_literal: true

module HydroHandlers
  module DependencyGraph
    class GraphChanges
      ECOSYSTEMS = {
        ECOSYSTEM_GO: PackageManagers::GO_MODULES,
        ECOSYSTEM_NPM: PackageManagers::NPM_AND_YARN,
      }.freeze

      class GraphChange
        attr_reader :package_manager, :directory

        def initialize(package_manager:, directory:)
          @package_manager = package_manager
          @directory = directory
        end
      end

      def self.from_message(message)
        new(message.value.fetch(:graph_changes))
      end

      # In the event we need to onboard a repository, we need to relay this
      # part of the original message through ActiveJob.
      #
      # This method acts as an entrypoint we test to ensure we decode and
      # handle the idiosyncratic behaviour around symbol/string conversion.
      def self.from_active_job(hash)
        new(hash.with_indifferent_access.fetch(:graph_changes))
      end

      def initialize(changes)
        @changes = changes.map do |change|
          GraphChange.new(
            package_manager: ECOSYSTEMS.fetch(change[:ecosystem].to_sym, nil),
            directory: change[:directory]
          )
        end
      end
      private_class_method :new

      def each(&)
        @changes.each(&)
      end
    end
  end
end
