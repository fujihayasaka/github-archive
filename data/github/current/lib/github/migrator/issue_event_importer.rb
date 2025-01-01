# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class IssueEventImporter < GitHub::Migrator::Importer

      def import(attributes, options = {})
        issue_event = IssueEvent.new do |issue_event|
          issue_event.issue = \
            model_from_source_url!(attributes["issue"]) ||
            model_from_source_url!(attributes["pull_request"]).try(:issue)

          issue_event.actor = user_or_fallback(attributes["actor"])
          issue_event.event = attributes["event"]
          issue_event.created_at = attributes["created_at"]

          # Under normal circumstances, these repository_id values would be
          # populated via validation callbacks, but on import we are swallowing
          # validation errors and continuing with record creation, so we need
          # to explicitly set these values in order for them to work in
          # a sharded cluster.
          issue_event.repository_id = issue_event.issue&.repository_id
          issue_event.issue_event_detail.repository_id = issue_event.repository_id

          if label_name = last_part_of_url(attributes["label"])
            if label = issue_event.issue&.repository&.labels&.where(name: label_name)&.first
              issue_event.label_id = label.id
            end
          end

          %w[label_name label_color label_text_color
           milestone_title title_was title_is deployment_id
           ref before_commit_oid after_commit_oid].each do |key|

            if value = attributes[key]
              issue_event.send("#{key}=", value)
            end
          end

          issue_event.column_name = attributes["column_name"]
          issue_event.previous_column_name = attributes["previous_column_name"]

          if attributes["subject"]
            issue_event.subject = model_from_source_url!(attributes["subject"])
          end

          if referencing_issue = attributes["referencing_issue"]
            issue_event.referencing_issue = model_from_source_url!(referencing_issue)
          end

          if referencing_pull_request = attributes["referencing_pull_request"]
            issue_event.referencing_issue = model_from_source_url!(referencing_pull_request).issue
          end

          if commit_id = attributes["commit_id"]
            issue_event.commit_id = commit_id
          end

          if commit_repository = attributes["commit_repository"]
            issue_event.commit_repository = model_from_source_url!(commit_repository)
          end
        end

        imported_issue_event = import_model(issue_event)
        issue_event.issue_event_detail.issue_event_id = imported_issue_event.id
        import_model(issue_event.issue_event_detail)

        ImporterResult.new(
          imported_issue_event.reload
        )
      rescue GitHub::Migrator::AssociationFailed => error
        log_and_create_importer_result(
          attributes,
          error,
          "Skipped import: encountered a GitHub::Migrator::AssociationFailed error",
          "issue_event",
          "skipped"
        )
      rescue ActiveRecord::RecordNotUnique => error
        log_and_create_importer_result(
          attributes,
          error,
          "Skipped import: encountered an ActiveRecord::RecordNotUnique error",
          "issue_event",
          "skipped"
        )
      rescue ActiveRecord::StatementInvalid => error
        log_and_create_importer_result(
          attributes,
          error,
          "Skipped import: invalid or unsupported issue event with type:[#{attributes["event"]}]",
          "issue_event",
          "skipped"
        )
      end
    end
  end
end
