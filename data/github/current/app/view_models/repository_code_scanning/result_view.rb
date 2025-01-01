# typed: true
# frozen_string_literal: true

module RepositoryCodeScanning
  class ResultView < View
    include ActionView::Helpers::TagHelper

    attr_reader :blob_map, :commit_map, :selected_alert_instance

    def result
      response&.data&.result
    end

    def related_locations
      @related_locations ||= response&.data&.related_locations || []
    end

    def location
      alert_instance&.location
    end

    def tool_name
      result&.tool&.name
    end

    def rule_query_uri
      response&.data&.result&.rule&.query_uri
    end

    def blob_for(location)
      blob_map[location.file_path] if location
    end

    def commit_for(commit_oid)
      commit_map[commit_oid]
    end

    # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
    def alert_instance
      @alert_instance ||= selected_alert_instance || result&.most_recent_instance
    end
    # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

    def markdown_message_text?
      result.message_markdown.present?
    end

    def rich_result_message_text
      context = {
        related_locations: related_locations,
        entity: repository,
        commit_oid: alert_instance&.commit_oid,
      }
      if markdown_message_text?
        GitHub::Goomba::CodeScanningMarkdownPipeline.to_html(result.message_markdown, context, nil)
      else
        GitHub::Goomba::CodeScanningMessagePipeline.to_html(result.message_text, context, nil)
      end
    end

    def location_matches_result(candidate)
      location.file_path == candidate.file_path &&
        location.start_line == candidate.start_line &&
        location.end_line == candidate.end_line &&
        location.start_column == candidate.start_column &&
        location.end_column == candidate.end_column
    end

    def snippet_message_classes
      class_names(
        "color-border-default": result.rule_severity == :NOTE,
        "code-scanning-alert-warning-message": result.rule_severity == :WARNING,
        "color-border-danger-emphasis": result.rule_severity == :ERROR,
      )
    end

    def is_codeql?
      CodeScanning::Tool.canonical_name(tool_name) == "CodeQL"
    end

    def snippet_helper(location, commit_oid)
      message = location_matches_result(location) ? rich_result_message_text : nil
      blob = blob_for(location)
      commit = commit_for(commit_oid)
      location_hash = {
        start_line: location.start_line,
        end_line: location.end_line,
        start_column: location.start_column,
        end_column: location.end_column,
      }
      RepositoryScanning::CodeSnippetHelper.new(blob, location_hash, commit: commit, message_text: message, message_classes: snippet_message_classes, highlight_location_lines: false)
    end

    def code_paths_url
      urls.repository_code_scanning_code_paths_path(repository.owner, repository, number: result.number, ref: alert_instance&.ref_name_bytes)
    end

    def rule_sarif_identifier
      result&.rule&.sarif_identifier
    end
  end
end
