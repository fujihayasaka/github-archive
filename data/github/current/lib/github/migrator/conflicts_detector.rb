# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class ConflictsDetector
      autoload :Base, "github/migrator/conflicts_detector/base"
      autoload :OrganizationConflictsDetector, "github/migrator/conflicts_detector/organization_conflicts_detector"
      autoload :ProjectConflictsDetector, "github/migrator/conflicts_detector/project_conflicts_detector"
      autoload :RepositoryConflictsDetector, "github/migrator/conflicts_detector/repository_conflicts_detector"
      autoload :TeamConflictsDetector, "github/migrator/conflicts_detector/team_conflicts_detector"
      autoload :UserConflictsDetector, "github/migrator/conflicts_detector/user_conflicts_detector"

      include MigratorHelper

      attr_reader :guid, :organization, :archive_url_templates, :max_conflicts

      def initialize(guid:, organization: nil, archive_url_templates: DefaultUrlTemplates, max_conflicts: nil)
        @guid = guid
        @organization = organization
        @archive_url_templates = archive_url_templates
        @max_conflicts = max_conflicts
      end

      def call
        generated_conflicts = 0

        MIGRATABLE_MODELS.each do |migratable_model|
          next unless migratable_model.check_for_conflicts?

          migratable_resources = current_migration.by_model_type(
            migratable_model.model_type,
          ).not_mapped.not_final

          migratable_resources.find_each do |migratable_resource|
            # stop generating conflicts if we've generated max_conflicts conflicts
            if should_limit_conflicts? && generated_conflicts >= max_conflicts
              return
            end

            model_type = migratable_resource.model_type
            source_url = migratable_resource.source_url

            detector = self.class.const_get(
              "#{migratable_model.model_type.classify}ConflictsDetector",
            )

            result = detector.call(
              migratable_resource: migratable_resource,
              migration_scope: organization,
              current_migration: current_migration,
              archive_url_templates: archive_url_templates,
              model_url_service: model_url_service,
              cache: cache,
            )

            if result.conflict?
              yield(
                model_type,
                source_url,
                result.target_url,
                result.action,
                result.notes
              )

              generated_conflicts += 1
            end
          end
        end
      ensure
        cache.clear
      end

      def conflicts?
        has_conflicts = T.let(false, T::Boolean)

        call do
          has_conflicts = true
          break
        end

        has_conflicts
      ensure
        cache.clear
      end

      def should_limit_conflicts?
        max_conflicts.present?
      end
    end
  end
end
