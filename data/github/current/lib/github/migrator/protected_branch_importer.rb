# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class ProtectedBranchImporter < GitHub::Migrator::Importer
      include RepoHelpers
      include GitHub::Rsync

      def import(attributes, options = {})
        protected_branch_attributes = attributes.slice(
          "admin_enforced",
          "block_deletions_enforcement_level",
          "block_force_pushes_enforcement_level",
          "dismiss_stale_reviews_on_push",
          "name",
          "pull_request_reviews_enforcement_level",
          "require_code_owner_review",
          "required_status_checks_enforcement_level",
          "strict_required_status_checks_policy",
        ).merge(
          repository: model_from_source_url(attributes["repository_url"]),
          creator:    user_or_fallback(attributes["creator_url"]),
        )

        protected_branch = import_model(
          ProtectedBranch.new(protected_branch_attributes),
        )

        if protected_branch.repository.owner.is_a?(Organization)

          # Only set push retrictions if they are enabled
          protected_branch.replace_authorized_actors(
            user_ids: ids_from_urls(attributes["authorized_user_urls"]),
            team_ids: ids_from_urls(attributes["authorized_team_urls"]),
            entry_point: :protected_branch_importer,
          ) if attributes["authorized_actors_only"]

          protected_branch.replace_dismissal_restricted_actors(
            user_ids: ids_from_urls(attributes["dismissal_restricted_user_urls"]),
            team_ids: ids_from_urls(attributes["dismissal_restricted_team_urls"]),
          ) if should_import_review_dismissals?(attributes)
        end

        attributes["required_status_checks"].each do |context|
          RequiredStatusCheck.create!(
            protected_branch: protected_branch,
            context:          context,
          )
        end

        protected_branch
      end

      def should_import_review_dismissals?(attributes)
        return attributes["restricts_review_dismissals"] if attributes["restricts_review_dismissals"] || attributes["restricts_review_dismissals"] == false

        # This accounts for the case where the archive doesn't have restricts_review_dismissals attribute set
        attributes["dismissal_restricted_team_urls"].any? || attributes["dismissal_restricted_user_urls"].any?
      end

      def ids_from_urls(urls)
        urls.map do |url|
          model_from_source_url(url)&.id
        end.compact
      end
    end
  end
end
