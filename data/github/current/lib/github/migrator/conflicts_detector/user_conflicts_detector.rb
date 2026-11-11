# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class ConflictsDetector
      class UserConflictsDetector < Base
        def call
          return no_conflict unless reference_url.present?

          super
        end

        protected

        def model
          super || existing_mannequin(migratable_resource, reference_url)
        end

        def conflicting_model_found?
          super && !skipping_to_mannequin?
        end

        def apply_recommended_action
          return ghost_user_conflict if model_is_ghost?
          return super unless scoped_migration?
          return super if model.is_a?(Mannequin)
          return super if migration_scope.member?(model)

          return no_conflict if migratable_resource.skip?

          ConflictDetectionResult.new(
            target_url: reference_url,
            action: :skip,
            notes: "User exists on target, but is not a member of the importing Organization",
          )
        end

        def requires_existing_model?
          scoped_migration? && !migratable_resource.skip?
        end

        def model_must_exist
          ConflictDetectionResult.new(
            target_url: mannequin_url(migratable_resource),
            action: :skip,
            notes: "User does not exist on target",
          )
        end

        def invalid_url
          return super unless scoped_migration?

          # This means we have already resolved this skip conflict
          return no_conflict if migratable_resource.skip?

          ConflictDetectionResult.new(
            target_url: mannequin_url(migratable_resource),
            action: :skip,
            notes: "Invalid value in url",
          )
        end

        def model_is_ghost?
          model.ghost?
        end

        def ghost_user_conflict
          ConflictDetectionResult.new(
            target_url: File.join(GitHub.url, User.ghost.login),
            action: :map,
            notes: "Ghost user already exists on target",
          )
        end

        def skipping_to_mannequin?
          migratable_resource.skip? && model.mannequin?
        end

        def existing_mannequin(migratable_resource, url)
          return unless migratable_resource.skip?
          return unless scoped_migration?

          login = url_translator.extract(target_url_templates["user"], url)["user"]
          migration_scope.mannequins.find_by(source_login: login)
        end

        def mannequin_url(migratable_resource)
          # TODO: this should make use of URL templates in the future
          login = migratable_resource.source_url.split("/").last

          url_for_model(Mannequin.new(source_login: login), use_cache: false)
        end
      end
    end
  end
end
