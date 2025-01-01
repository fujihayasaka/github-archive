# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class ConflictsDetector
      class OrganizationConflictsDetector < Base

        protected

        def apply_recommended_action
          return super unless scoped_migration? && !model_is_migration_scope?

          org_map_conflict
        end

        def requires_existing_model?
          scoped_migration?
        end

        def model_must_exist
          org_map_conflict
        end

        def invalid_url
          return super unless scoped_migration?

          # Always recommend mapping to importing org on invalid URLs
          org_map_conflict
        end

        def model_is_migration_scope?
          model == migration_scope
        end

        def org_map_conflict
          ConflictDetectionResult.new(
            target_url: url_for_model(migration_scope),
            action: migratable_model.recommended_action,
            notes: "Organizations must be mapped to importing Organization",
          )
        end
      end
    end
  end
end
