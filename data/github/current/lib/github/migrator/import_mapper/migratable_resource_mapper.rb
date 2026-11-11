# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class ImportMapper
      class MigratableResourceMapper
        include MigratorHelper

        MAP_OR_RENAME_ACTIONS = [nil, :map_or_rename].freeze

        # These models types must be set with the `map` action when importing
        # to an organization (such as when importing to GitHub.com)
        MODEL_TYPES_REQUIRING_MAPPING = %w[organization user].freeze

        attr_reader :migratable_resource, :mapping_input, :action, :organization
        attr_writer :action

        delegate :source_url, :target_url, :model_type, to: :mapping_input

        def initialize(migratable_resource:, mapping_input:, organization: nil)
          @migratable_resource = migratable_resource
          @mapping_input       = mapping_input
          @organization        = organization

          self.action = mapping_input.action
        end

        def self.call(**named_args)
          new(**T.unsafe(named_args)).call
        end

        def call
          migratable_resource.model_type ||= model_type
          migratable_resource.target_url = target_url

          if action == :skip
            attempt_skip
          else
            attempt_map_or_rename
          end

          migratable_model = migratable_model_for(migratable_resource.model_type)
          if migratable_model.blank?
            failed_mapping!(
              "Model name required because it cannot be inferred from a " \
              "pre-existing record",
            )
          elsif !migratable_model.mapping_actions.include?(action)
            failed_mapping!(
              "Unsupported action #{action} for " \
              "#{migratable_resource.model_type}, must be one of " \
              "#{migratable_model.mapping_actions.join(", ")}",
            )
          end

          migratable_resource.warning = nil
          migratable_resource.state = action
        end

        private

        def attempt_skip
          unless organization
            failed_mapping!("Cannot skip without a migration scope")
          end

          user = model_for_url(target_url)
          if organization.member?(user)
            failed_mapping!(
              "Cannot skip and use the URL #{target_url} because there is " \
              "already a user with that URL",
            )
          end

          if model = mannequin_for_url(target_url)
            migratable_resource.model_id = model.id
          end
        end

        def attempt_map_or_rename
          model = model_for_url(target_url)
          if model
            ensure_no_rename_to_existing_model!

            self.action = :conflict if model_outside_target_scope?(model)
            migratable_resource.model_id = model.id unless action == :conflict
            self.action = :map if should_map_or_rename?
          elsif action == :map
            cannot_map_without_model!
          else
            self.action = :rename if should_map_or_rename?

            if model_type_requires_map_action?
              failed_mapping!(
                "Unsupported action #{action} for " \
                "#{migratable_resource.model_type}. This operation is not " \
                "supported.",
              )
            end
          end
        end

        def ensure_no_rename_to_existing_model!
          if action == :rename
            failed_mapping!(
              "Cannot rename #{source_url} to #{target_url} because target already exists",
              exception: CannotRenameToExistingModel,
            )
          end
        end

        def model_outside_target_scope?(model)
          return false unless scoped_migration?
          invalid_map_org?(model) || invalid_map_user?(model)
        end

        def invalid_map_org?(model)
          model.is_a?(Organization) && model != organization
        end

        def invalid_map_user?(model)
          return false unless model.is_a?(User) && model.user?
          return false if model.ghost?
          !organization.member?(model)
        end

        def should_map_or_rename?
          MAP_OR_RENAME_ACTIONS.include?(action)
        end

        def cannot_map_without_model!
          if model_type_requires_map_action?
            self.action = :conflict
          else
            failed_mapping!(
              "Cannot map #{source_url} to #{target_url} because target could not be found",
              exception: CannotMapToMissingTarget,
            )
          end
        end

        def model_type_requires_map_action?
          scoped_migration? && MODEL_TYPES_REQUIRING_MAPPING.include?(model_type)
        end

        def scoped_migration?
          organization.present?
        end

        def failed_mapping!(message, exception: FailedMapping)
          migratable_resource.warning = message
          raise(exception, message)
        end

        def mannequin_for_url(url)
          return unless scoped_migration?

          # TODO: this should make use of URL templates in the future
          login = url.split("/").last

          # Temporary refactor until we find a better way to optimize original
          # organization.mannequins call. This call executes quickly if the
          # org has fewer than 200 migrations, which should be the case for
          # most orgs.
          #
          # See https://github.com/github/data-liberation/issues/304
          #
          mannequins.find_by(source_login: login)
        end

        def mannequins
          organization.mannequins
        end
      end
    end
  end
end
