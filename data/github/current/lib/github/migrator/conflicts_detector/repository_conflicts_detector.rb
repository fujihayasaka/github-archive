# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class ConflictsDetector
      class RepositoryConflictsDetector < Base

        protected

        def unresolvable_conflict
          new_conflict(:conflict, "User repository imports are not supported.")
        end

        def owned_by_org?
          parent_mr = parent_migratable_resource(parent_org_url)
          parent_mr.present? && parent_mr.model_type == "organization"
        end

        def unsupported_import_found?
          return unless scoped_migration?
          !owned_by_org?
        end

        def apply_recommended_action
          ConflictDetectionResult.new(
            action: :rename,
            target_url: url_for_model(model),
            notes: notes
          )
        end

        def notes
          return nil unless target_url_present?

          migratable_resource.warning
        end

        alias_method :unrewritten_url, :reference_url
        def reference_url
          if parent_organization_model
            parent_model_url(parent_organization_model)
          elsif parent_user_model
            parent_model_url(parent_user_model)
          end
        end

        def parent_model_url(model)
          url_params = target_url_present? ? target_url_params : repo_url_params

          url_translator.expand(
            target_url_templates["repository"],
            url_params.merge(
              url_translator.default_params,
            ).merge(
              "owner" => model.login,
            ),
          )
        end

        def has_invalid_url?
          url_invalid?(unrewritten_url)
        end

        ##
        # Extracts org and repo name from the original URL
        #
        def repo_url_params
          url_translator.extract(
            source_url_templates["repository"],
            migratable_resource.source_url,
          )
        end

        def target_url_params
          url_translator.extract(
            target_url_templates["repository"],
            migratable_resource.target_url,
          )
        end

        def target_url_present?
          migratable_resource.target_url.present?
        end

        ##
        # Generates an org URL based off the repos's URL
        #
        def parent_org_url
          url_translator.expand(
            source_url_templates["organization"],
            repo_url_params.merge("organization" => repo_url_params["owner"]),
          )
        end

        ##
        # Generates a user URL based off the repos's URL
        #
        def parent_user_url
          url_translator.expand(
            source_url_templates["user"],
            repo_url_params.merge("user" => repo_url_params["owner"]),
          )
        end

        ##
        # Looks up parent org migratable resource and returns the model
        #
        def parent_organization_model
          parent_mr = parent_migratable_resource(parent_org_url)
          return unless parent_mr.present?

          model = parent_mr.model
          model if model.present? && model.organization?
        end

        ##
        # Looks up parent user migratable resource and returns the model
        #
        def parent_user_model
          parent_mr = parent_migratable_resource(parent_user_url)
          return unless parent_mr.present?

          model = parent_migratable_resource(parent_user_url).model
          model if model.present? && model.user?
        end

        def parent_migratable_resource(source_url)
          current_migration.where(source_url: source_url).first
        end
      end
    end
  end
end
