# typed: strict
# frozen_string_literal: true

module Exporter
  class SerializerFactory
    sig do
      params(
        migratable_model: GitHub::Migrator::MigratableModel,
        actor: User,
        owner: User,
        options: ExportOptions,
        migration_guid: String
      ).returns(GitHub::Migrator::BaseSerializer)
    end
    def self.create(migratable_model:, actor:, owner:, options:, migration_guid:)
      model_url_service = GitHub::Migrator::ModelUrlService.new(
        cache: GitHub::Migrator::Cache.new
      )

      migratable_model.serializer.new(
        model_url_service: model_url_service,
        actor: actor,
        owner: owner,
        org_metadata_only: options.org_metadata_only
      )
    end
  end
end
