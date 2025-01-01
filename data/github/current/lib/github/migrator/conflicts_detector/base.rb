# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class ConflictsDetector
      class Base
        include MigratorHelper

        attr_reader :migratable_resource, :migration_scope, :current_migration,
          :archive_url_templates, :target_url, :notes

        def initialize(migratable_resource:, migration_scope:, current_migration:, archive_url_templates:, model_url_service: nil, cache: nil)
          @migratable_resource   = migratable_resource
          @migration_scope       = migration_scope
          @current_migration     = current_migration
          @archive_url_templates = archive_url_templates
          @model_url_service     = model_url_service
          @cache                 = cache
        end

        def self.call(**kargs)
          self.new(**T.unsafe(kargs)).call
        end

        def call
          return unresolvable_conflict if unsupported_import_found?
          return apply_recommended_action if conflicting_model_found?
          return invalid_url if has_invalid_url?
          return model_must_exist if requires_existing_model?

          no_conflict
        end

        protected

        def reference_url
          migratable_resource.target_url || migratable_resource.source_url
        end

        def source_url_templates
          url_translator.from
        end

        def target_url_templates
          url_translator.to
        end

        def model
          model_for_url(reference_url)
        end

        def model_type
          migratable_resource.model_type
        end

        def migratable_model
          migratable_model_for(model_type)
        end

        def scoped_migration?
          migration_scope.present?
        end

        def conflicting_model_found?
          model.present?
        end

        def has_invalid_url?
          url_invalid?(reference_url)
        end

        def requires_existing_model?
          false
        end

        def unsupported_import_found?
          false
        end

        def apply_recommended_action
          ConflictDetectionResult.new(
            target_url: url_for_model(model),
            action: migratable_model.recommended_action,
          )
        end

        def unresolvable_conflict
          new_conflict(:conflict, "This model cannot be imported.")
        end

        def invalid_url
          ConflictDetectionResult.new(
            action: :rename,
            notes: "Invalid value in url",
          )
        end

        def model_must_exist
          # no-op
        end

        def no_conflict
          ConflictDetectionResult.new
        end

        def new_conflict(action, notes)
          ConflictDetectionResult.new(action: action, notes: notes)
        end

        class ConflictDetectionResult
          attr_reader :target_url, :action, :notes

          def initialize(target_url: nil, action: nil, notes: nil)
            @target_url = target_url
            @action     = action
            @notes      = notes
          end

          def conflict?
            [target_url, action, notes].any?
          end
        end
      end
    end
  end
end
