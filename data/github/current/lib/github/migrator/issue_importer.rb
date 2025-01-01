# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class IssueImporter < GitHub::Migrator::Importer

      def import(attributes, options = {})
        repo = model_from_source_url!(attributes["repository"])

        issue = Issue.new do |issue|
          issue.repository = repo
          issue.user = user_or_fallback(attributes["user"])
          issue.number = last_part_of_url(attributes["url"]).to_i
          issue.pull_request_id = attributes["pull_request_id"]
          issue.title = attributes["title"]
          issue.body = attributes["body"]
          issue.assignee = model_from_source_url(attributes["assignee"])
          issue.milestone = model_from_source_url(attributes["milestone"])
          issue.created_at = attributes["created_at"]
          issue.updated_at = attributes["updated_at"] || attributes["created_at"]
          if attributes["closed_at"]
            issue.closed_at = attributes["closed_at"]
            issue.state = "closed"
          end
        end

        import_model(issue).tap do |imported_issue|
          assignees(attributes).each do |assignee|
            Assignment.create({
              issue: imported_issue,
              assignee: assignee,
              skip_trigger_assigned_event: true,
              skip_ensure_assignee_is_a_collaborator: true,
              skip_touch_issue_updated_at: true
            })
          end
        end
      end

      private

      def assignees(attributes)
        assignee_urls(attributes).map do |assignee_url|
          model_from_source_url(assignee_url)
        end.compact
      end

      def assignee_urls(attributes)
        [
          attributes["assignee"],
          attributes["assignees"],
        ].flatten.uniq.compact
      end
    end
  end
end
