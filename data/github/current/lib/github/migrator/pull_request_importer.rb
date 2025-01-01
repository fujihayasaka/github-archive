# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class PullRequestImporter < GitHub::Migrator::Importer

      def import(attributes, options = {})
        pull_request = PullRequest.new do |pr|
          pr.repository = repository!(attributes)
          pr.user = user_or_fallback(attributes["user"])
          pr.base_repository = model_from_source_url!(attributes["base"]["repo"])
          pr.base_user = base_user!(attributes)
          pr.base_ref = attributes["base"]["ref"]
          pr.base_sha = attributes["base"]["sha"]
          pr.merge_commit_sha = attributes["merge_commit_sha"]

          # Workaround for pull requests from forks that aren't being migrated.
          # Tries to find the head repo first and then uses a fallback option
          # if it does not exist.
          if model = model_from_source_url(attributes["head"]["repo"])
            pr.head_repository = model
            pr.head_user = head_or_base_user!(attributes)
            pr.head_ref = attributes["head"]["ref"]
          else
            # Set head repo/user to base repo/user.
            pr.head_repository = model_from_source_url!(attributes["base"]["repo"])
            pr.head_user = base_user!(attributes)
            # Create a fake head ref that looks like it references the fork.
            pr.head_ref = "#{last_part_of_url(attributes["head"]["user"])}/#{attributes["head"]["ref"]}"
          end

          pr.head_sha = attributes["head"]["sha"]

          if attributes["merged_at"]
            pr.merged_at = attributes["merged_at"]
            pr.mergeable = nil
          end

          if attributes["work_in_progress"]
            pr.work_in_progress = attributes["work_in_progress"]
          end

          if attributes["closed_at"]
            pr.status = "closed"
          else
            pr.status = "open"
          end

          pr.created_at = attributes["created_at"]
        end

        import_model(pull_request).tap do |pr|
          issue_importer.import(attributes.merge({
            "pull_request_id" => pr.id,
          }))
          import_review_requests(
            pull_request: pr,
            review_requests: attributes["review_requests"],
          )
        end
      end

      def import_review_requests(pull_request:, review_requests:)
        Array(review_requests).each do |request|
          next unless request["reviewer"]

          review_request = ReviewRequest.new(
            pull_request:  pull_request,
            reviewer:      model_from_source_url!(request["reviewer"]),
            reviewer_type: request["reviewer_type"],
            created_at:    request["created_at"],
            updated_at:    request["updated_at"],
            dismissed_at:  request["dismissed_at"],
            # Under normal circumstances, this repository_id value would be
            # populated via validation callbacks, but on import we are swallowing
            # validation errors and continuing with record creation, so we need
            # to explicitly set these values in order for them to work in
            # a sharded cluster.
            repository_id: pull_request.repository_id
          )

          import_model(review_request)
        rescue GitHub::Migrator::AssociationFailed => error
          GitHub.logger.error("Skipped review request import: failed to find reviewer in archive", {
            :exception => error,
            "code.function" => "import_review_requests",
            "code.namespace" => "GitHub::Migrator::PullRequestImporter",
            "gh.migration_tools.migration.type" => "repo",
            "gh.migration_tools.migration.model.name" => "pull_request",
            "gh.migration_tools.migration.model.source_url" => request["reviewer"],
            "gh.migration_tools.migration.model.resolution" => "skipped",
            "gh.migration_tools.migration.guid" => migration_guid
            }
          )
          next
        end
      end

      private

      def head_or_base_user!(attributes)
        user = head_user!(attributes)
        return base_user!(attributes) if user.mannequin?
        user
      end

      def head_user!(attributes)
        model_from_source_url!(attributes["head"]["user"]) || repository!(attributes).owner
      end

      def base_user!(attributes)
        model_from_source_url!(attributes["base"]["user"]) || repository!(attributes).owner
      end

      def repository!(attributes)
        model_from_source_url!(attributes["repository"])
      end

      def issue_importer
        @issue_importer ||= IssueImporter.new(importer_options)
      end
    end
  end
end
