# frozen_string_literal: true

module HydroHandlers
  module DependencyGraph
    class GraphChanges
      include Enumerable
      ECOSYSTEMS = {
        ECOSYSTEM_GO: PackageManagers::GO_MODULES,
        ECOSYSTEM_NPM: PackageManagers::NPM_AND_YARN,
        ECOSYSTEM_NUGET: PackageManagers::NUGET,
        ECOSYSTEM_PYPI: PackageManagers::PIP,
      }.freeze

      class GraphChange
        attr_reader :package_manager, :directory, :ref_name, :commit_oid

        def initialize(package_manager:, directory:, ref_name:, commit_oid: nil)
          @package_manager = package_manager
          @directory = directory
          @ref_name = ref_name
          @commit_oid = commit_oid
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
            directory: change[:directory],
            ref_name: change[:ref_name],
            commit_oid: change[:commit_oid],
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
