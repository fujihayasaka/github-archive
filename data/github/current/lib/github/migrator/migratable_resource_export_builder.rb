# typed: true
# frozen_string_literal: true

require "github/migrator/batch_service"

module GitHub
  class Migrator
    class MigratableResourceExportBuilder
      BATCH_SIZE = 50
      DEFAULT_PROGRESS = lambda { |_type, _value| }

      BATCH_INSERT_SQL = <<~BATCH_INSERT_SQL
        INSERT IGNORE INTO
          #{MigratableResource.table_name}
          (guid,model_type,model_id,source_url,state,created_at,updated_at)
        :migratable_resources_values
      BATCH_INSERT_SQL

      def initialize(guid:, model_url_service:, progress: DEFAULT_PROGRESS)
        @guid              = guid
        @model_url_service = model_url_service
        @progress          = progress
      end

      attr_reader :guid, :model_url_service, :progress

      def add(model)
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
        user_ids.each_slice(BATCH_SIZE) do |ids|
          User.where(id: ids).each do |user|
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
        add(model)
        batch_insert_migratable_resources.complete
      rescue ActiveRecord::Deadlocked
        raise GitHub::Migrator::ExportFailure.new("Failed to generate migratable resource due to database issues.")
      rescue ActiveRecord::ConnectionFailed
        raise GitHub::Migrator::ExportFailure.new("Failed to generate migratable resource due to database connection failure.")
      end

      private

      delegate :url_for_model, to: :model_url_service

      def user_ids
        @user_ids ||= Set.new
      end

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

          ActiveRecord::Base.connected_to(role: :writing) do
            MigratableResource.connection.insert(
              Arel.sql(BATCH_INSERT_SQL, migratable_resources_values: migratable_resources_values)
            )
          end

          progress.call(:progress_with_count, models.size)
        end
      end
    end
  end
end
