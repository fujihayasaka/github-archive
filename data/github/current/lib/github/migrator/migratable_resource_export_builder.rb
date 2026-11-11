# typed: true
# frozen_string_literal: true

require "github/migrator/batch_service"

module GitHub
  class Migrator
    class MigratableResourceExportBuilder
      BATCH_SIZE = 50
      DEFAULT_PROGRESS = lambda { |_type, _value| }

      # rubocop:disable GitHub/InsertOnDuplicateKeyUpdate
      BATCH_INSERT_SQL = <<~BATCH_INSERT_SQL
        INSERT INTO
          #{MigratableResource.table_name}
          (guid,model_type,model_id,source_url,state,created_at,updated_at)
        :migratable_resources_values
        ON DUPLICATE KEY UPDATE
          updated_at = VALUES(updated_at)
      BATCH_INSERT_SQL
      # rubocop:enable GitHub/InsertOnDuplicateKeyUpdate

      BATCH_INSERT_IGNORE_SQL = <<~BATCH_INSERT_IGNORE_SQL
        INSERT IGNORE INTO
          #{MigratableResource.table_name}
          (guid,model_type,model_id,source_url,state,created_at,updated_at)
        :migratable_resources_values
      BATCH_INSERT_IGNORE_SQL

      def initialize(guid:, model_url_service:, progress: DEFAULT_PROGRESS, exclude_git_data: false, org_metadata_only: false, export_batch_enabled: false)
        @guid              = guid
        @model_url_service = model_url_service
        @progress          = progress
        @exclude_git_data  = exclude_git_data
        @org_metadata_only = org_metadata_only
        @export_batch_enabled = export_batch_enabled
      end

      attr_reader :guid, :model_url_service, :progress, :exclude_git_data, :org_metadata_only

      def add(model)
        return migratable_resource_export_builder_adapter.add(model) if use_batched_export?

        case model
        when Hash
          user_id = model.fetch(:user_id)
          user_ids.add(user_id)
        when nil
          nil  # skip adding unreferenceable models
        else
          batch_insert_migratable_resources.add(model)
        end
      rescue ActiveRecord::Deadlocked
        raise GitHub::Migrator::ExportFailure.new("Failed to generate migratable resource due to database issues.")
      rescue ActiveRecord::ConnectionFailed
        raise GitHub::Migrator::ExportFailure.new("Failed to generate migratable resource due to database connection failure.")
      end

      def complete
        return migratable_resource_export_builder_adapter.complete if use_batched_export?

        user_ids.each_slice(BATCH_SIZE) do |ids|
          User.where(id: ids).each do |user|
            # Skip users that don't have a valid URL (e.g., deleted users)
            next if url_for_model(user).nil?

            batch_insert_migratable_resources.add(user)
          end
        end

        batch_insert_migratable_resources.complete
      rescue ActiveRecord::Deadlocked
        raise GitHub::Migrator::ExportFailure.new("Failed to generate migratable resource due to database issues.")
      rescue ActiveRecord::ConnectionFailed
        raise GitHub::Migrator::ExportFailure.new("Failed to generate migratable resource due to database connection failure.")
      end

      def add_now(model)
        return migratable_resource_export_builder_adapter.add_now(model) if use_batched_export?

        add(model)
        batch_insert_migratable_resources.complete
      rescue ActiveRecord::Deadlocked
        raise GitHub::Migrator::ExportFailure.new("Failed to generate migratable resource due to database issues.")
      rescue ActiveRecord::ConnectionFailed
        raise GitHub::Migrator::ExportFailure.new("Failed to generate migratable resource due to database connection failure.")
      end

      private

      def use_batched_export?
        @export_batch_enabled
      end

      def migratable_resource_export_builder_adapter
        @migratable_resource_export_builder_adapter ||= ::Exporter::Services::MigratableResourceExportBuilderAdapter.new(
          guid: guid,
          model_url_service: model_url_service,
          progress: progress,
          exclude_git_data: exclude_git_data,
          org_metadata_only: org_metadata_only
        )
      end

      def user_ids
        @user_ids ||= Set.new
      end

      delegate :url_for_model, to: :model_url_service

      def batch_insert_migratable_resources
        @batch_insert_migratable_resources ||= BatchService.new(
          retry_on: FeatureFlag.vexi.enabled?(:migrator_retry_connection_failed, default: false) ? [ActiveRecord::Deadlocked, ActiveRecord::ConnectionFailed] : ActiveRecord::Deadlocked
        ) do |models|
          migratable_resources_values = Arel::Nodes::ValuesList.new(
            models.map do |model|
              [
                guid,
                model.class.model_name.singular,
                model.id,
                url_for_model(model),
                MigratableResource.states[:export],
                GitHub::SQL::ArelLiterals::NOW,
                GitHub::SQL::ArelLiterals::NOW
              ]
            end
          )

          # Use INSERT ... ON DUPLICATE KEY UPDATE to avoid gap locking
          # that causes deadlocks with concurrent exports
          insert_sql = if FeatureFlag.vexi.enabled?(:migrator_export_optimizations, default: false)
            BATCH_INSERT_SQL
          else
            BATCH_INSERT_IGNORE_SQL
          end

          ActiveRecord::Base.connected_to(role: :writing) do
            MigratableResource.connection.insert(
              Arel.sql(insert_sql, migratable_resources_values: migratable_resources_values)
            )
          end

          progress.call(:progress_with_count, models.size)
        end
      end
    end
  end
end
