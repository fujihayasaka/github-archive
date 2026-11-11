# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class ImportMapper
      autoload :MigratableResourceMapper, "github/migrator/import_mapper/migratable_resource_mapper"
      autoload :MappingInput, "github/migrator/import_mapper/mapping_input"

      include MigratorHelper

      def initialize(guid:)
        @guid         = guid
        @cache        = GitHub::Migrator::Cache.new
        @batch_mapper = GitHub::Migrator::MigratableResourceBatchMapper.new(guid: guid)
      end

      def call(source_url, target_url = nil, action = nil, model_type = nil, organization: nil, batch_mappings: false)
        migratable_resource = migratable_resource_from_source_url(source_url)
        mapping_input = MappingInput.new(
          source_url: source_url,
          target_url: target_url,
          action:     action,
          model_type: model_type,
        )

        MigratableResourceMapper.call(
          migratable_resource: migratable_resource,
          mapping_input: mapping_input,
          organization: organization,
        )
      ensure
        batch_mapper.add(migratable_resource) if migratable_resource.valid?
        cache.clear
        process_batch unless batch_mappings
      end

      def process_batch
        batch_mapper.complete
      end

      private

      attr_reader :cache, :guid, :batch_mapper

      # Internal: Find or initialize MigratableResource by source_url, optionally
      # passing a block.
      #
      # source_url - String url.
      #
      # Returns a MigratableResource.
      def migratable_resource_from_source_url(source_url, &block)
        current_migration.by_source_url(source_url, &block)
      end
    end
  end
end
