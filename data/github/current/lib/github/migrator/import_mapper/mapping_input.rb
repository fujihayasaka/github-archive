# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class ImportMapper
      class MappingInput
        attr_reader :source_url, :target_url, :action, :model_type

        NO_TARGET_URL_REQUIRED = %i(skip).freeze

        def initialize(source_url:, target_url:, action: nil, model_type: nil)
          @source_url = source_url
          @target_url = target_url
          @action     = action&.to_sym
          @model_type = valid_model_types.delete(model_type)

          validate_target_url_present!
        end

        private

        def valid_model_types
          MigratableModels::MIGRATABLE_MODELS.map(&:model_type)
        end

        def validate_target_url_present!
          return if target_url.present?

          unless NO_TARGET_URL_REQUIRED.include?(action)
            raise ArgumentError, "missing argument: target_url"
          end
        end
      end
    end
  end
end
