# typed: strict
# frozen_string_literal: true

module Exporter
  class MigratableModelResolver
    MIGRATABLE_MODELS_BY_TYPE = T.let(
      GitHub::Migrator::MigratableModels::MIGRATABLE_MODELS.index_by(&:model_type),
      T::Hash[String, GitHub::Migrator::MigratableModel]
    )

    sig { params(model_type: String).returns(GitHub::Migrator::MigratableModel) }
    def self.resolve(model_type)
      MIGRATABLE_MODELS_BY_TYPE[model_type] ||
        raise(ArgumentError, "Unknown model type: #{model_type}")
    end
  end
end
