# typed: true
# frozen_string_literal: true

require "github/migrator/batch_service"

module GitHub
  class Migrator
    class MigratableResourceBatchMapper
      BATCH_INSERT_SQL = <<~BATCH_INSERT_SQL
        INSERT INTO
          #{MigratableResource.table_name}
          (guid,model_type,model_id,source_url,target_url,warning,state,created_at,updated_at)
        :migratable_resources_values
        ON DUPLICATE KEY UPDATE
            model_type = VALUES(model_type),
            model_id   = VALUES(model_id),
            target_url = VALUES(target_url),
            warning    = VALUES(warning),
            state      = VALUES(state),
            updated_at = VALUES(updated_at)
      BATCH_INSERT_SQL

      def initialize(guid:)
        @guid = guid
      end

      attr_reader :guid

      def add(migratable_resource)
        batch_insert_migratable_resources.add(migratable_resource)
      end

      def complete
        batch_insert_migratable_resources.complete
      end

      private

      def batch_insert_migratable_resources
        @batch_insert_migratable_resources ||= begin
          retry_on = FeatureFlag.vexi.enabled?(:migrator_retry_connection_failed, default: false) ? [ActiveRecord::Deadlocked, ActiveRecord::ConnectionFailed] : ActiveRecord::Deadlocked

          BatchService.new(retry_on: retry_on) do |migratable_resources|
            migratable_resources_values = Arel::Nodes::ValuesList.new(
              migratable_resources.map do |migratable_resource|
                [
                  guid,
                  migratable_resource.model_type,
                  migratable_resource.model_id,
                  migratable_resource.source_url,
                  migratable_resource.target_url,
                  migratable_resource.warning,
                  MigratableResource.states[migratable_resource.state],
                  GitHub::SQL::ArelLiterals::NOW,
                  GitHub::SQL::ArelLiterals::NOW
                ]
              end
            )

            ActiveRecord::Base.connected_to(role: :writing) do
              MigratableResource.connection.insert(
                Arel.sql(BATCH_INSERT_SQL, migratable_resources_values: migratable_resources_values)
              )
            end
          end
        end
      end
    end
  end
end
