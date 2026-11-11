# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    # Public: Unlocks a set of repositories that were successfully exported or
    # imported therefore this class can be used on either side of a migration.
    #
    # Initialization requires a migration `guid` in order to locate the
    # repositories for that migration.

    # Example:
    #
    #  > unlocker = GitHub::Migrator::MigratedRepositoriesUnlocker.new(:guid => "abcd1234")
    #  > unlocker.call
    # => [#<Repository>, #<Repository>]
    #
    # Returns an Array of Repository instances.
    class MigratedRepositoriesUnlocker
      def self.call(options, &block)
        new(options).call(&block)
      end

      def initialize(options = {})
        @guid = options.fetch(:guid)
      end

      attr_reader :guid

      def call
        unlocked_repositories = []

        for_each_successfully_migrated_repository do |repository|
          unlocked_repositories << unlock_repository(repository)
        end

        unlocked_repositories.compact
      end

      def for_each_successfully_migrated_repository
        current_migration.by_model_type("repository").find_each do |migratable_resource|
          next unless migratable_resource.succeeded?

          yield(migratable_resource.model)
        end
      end

      def unlock_repository(repository)
        return if repository.nil?

        if repository.respond_to?(:unlock_excluding_descendants!)
          repository.unlock_excluding_descendants!
        else
          repository.unlock!
        end

        repository
      end

      def current_migration
        @current_migration ||= MigratableResource.for_guid(guid)
      end
    end
  end
end
