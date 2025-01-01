# typed: strict
# frozen_string_literal: true

module CodeScanning
  class AlertAssignment
    ASSIGNEE_LIMIT = 10

    sig { params(repository: Repository, alert_numbers: T::Array[Integer], alert_titles: T::Hash[Integer, T.nilable(String)]).returns(T.nilable(T::Hash[Integer, T::Hash[Symbol, T.untyped]])) }
    def self.build_alerts_assignment_alerts(repository:, alert_numbers:, alert_titles:)
      default_branch_ref = repository.default_branch_ref
      return nil unless default_branch_ref.present?

      autofix_suggestions = CodeScanning::AutofixSuggestion.fetch_applicable_suggested_fix_alerts(
        repository:,
        alert_numbers:,
        head_commit_oid: default_branch_ref.commit.oid,
        ref_names_bytes: [default_branch_ref.qualified_name.b],
      )

      alerts_with_autofix_suggestions = {}
      autofix_suggestions.each do |alert_number, suggested_fix_alert|
        # Create the hydro event structure based on the Alert message definition
        alerts_with_autofix_suggestions[alert_number] = {
          alert_number: alert_number,
          alert_title: alert_titles[alert_number].presence || "Code scanning alert",
          alert_url: UrlHelpers.repository_code_scanning_result_url(repository.owner, repository, number: alert_number, host: GitHub.url),
          suggested_fix: {
            files: suggested_fix_alert.suggested_fix&.files&.map do |fix_file|
              {
                file_path: fix_file.file_path,
                diff_content: fix_file.diff_content
              }
            end || []
          }
        }
      end

      alerts_with_autofix_suggestions
    rescue CodeScanning::AutofixError => e
      GitHub.logger.info(
        "Assign to Copilot failed fetching valid autofix suggestions for repo: #{e}",
        "gh.owner.id" => repository.owner_id,
        "gh.repository.id" => repository.id,
      )
      nil
    end
  end
end
