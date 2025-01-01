# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator

    class MigrationReporter
      attr_reader :migratable_resource_scope
      attr_reader :extra

      def initialize(migratable_resource_scope, extra = {})
        @migratable_resource_scope = migratable_resource_scope
        @extra = extra
      end

      def self.migrator_result(migratable_resource_scope, extra = {})
        MigrationReporter.new(migratable_resource_scope, extra).migrator_result
      end

      def self.record_result_for(migration)
        MigrationReporter.new(migration.migratable_resources).record_result_for(migration)
      end

      # Internal: This method will build a hash of results by iterating through
      # MIGRATABLE_MODELS and calling count on the passed in migratable_resource_scope.
      #
      # Adds migratable_resource_scope #guid and optional extra Hash to result Hash.
      #
      # migratable_resource_scope - MigratableResource migration to count on.
      # extra - (optional) Hash with other results.
      def migrator_result
        result = GitHub::Migrator::MigratableModels::MIGRATABLE_MODELS.inject({ guid: migratable_resource_scope.guid }) do |result, migratable_model|
          model_type = model_type_key(migratable_model)
          result[model_type] = total_count_for_model_type(migratable_model.model_type)
          result
        end.merge(extra)

        result
      end

      def record_result_for(migration)
        GitHub::Migrator::MigratableModels::MIGRATABLE_MODELS.each do |migratable_model|
          MigratableResourceReport.create!(
            migration: migration,
            model_type: model_type_key(migratable_model),
            total_count: total_count_for_model_type(migratable_model.model_type),
            success_count: success_count_for_model_type(migratable_model.model_type),
            failure_count: failure_count_for_model_type(migratable_model.model_type),
          )
        end
      end

      private

      def success_count_for_model_type(model_type)
        MigratableResource.uncached do
          migratable_resource_scope.where(model_type: model_type).succeeded.count
        end
      end

      def failure_count_for_model_type(model_type)
        MigratableResource.uncached do
          migratable_resource_scope.where(model_type: model_type).failed.count
        end
      end

      def total_count_for_model_type(model_type)
        MigratableResource.uncached do
          migratable_resource_scope.where(model_type: model_type).count
        end
      end

      def model_type_key(migratable_model)
        migratable_model.model_type.pluralize.to_sym
      end
    end
  end
end
