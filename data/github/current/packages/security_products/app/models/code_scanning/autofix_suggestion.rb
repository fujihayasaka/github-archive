# typed: true
# frozen_string_literal: true

module CodeScanning
  class AutofixSuggestion < SimpleDelegator
    def self.generate(repository:, alert_numbers:, ref_names_bytes:, source:, pull_request_id: nil)
      GitHub::Turboscan::SuggestedFixes.generate_suggested_fix(
        repository_id: repository.id,
        alert_numbers:,
        ref_names_bytes:,
        source: source,
        pull_request_id:,
        public: repository.public?,

        # The user_id will be used for rate limits at the CAPI level. We will throttle the same user when they
        # have too many requests for fixes and when we have a higher rate limit.
        user_id: repository.owner_id
      )
    end

    # Returns also outdated and empty suggested fix alerts
    def self.fetch_all_suggested_fix_alerts(repository:, alert_numbers:, head_commit_oid:, ref_names_bytes: nil)
      response = GitHub::Turboscan::SuggestedFixes.suggested_fix(
        repository_id: repository.id,
        alert_numbers: alert_numbers,
        head_commit_oid: head_commit_oid,
        ref_names_bytes: ref_names_bytes || Array(repository.default_branch_ref.qualified_name)
      )
      raise CodeScanning::AutofixError.new("Something went wrong", status: :internal_server_error) if response.nil? || response.error || response.data.nil?

      response.data&.suggested_fix_alerts&.each_with_object({}) do |(alert_number, suggested_fix_alert), out|
        out[alert_number] = suggested_fix_alert
      end
    end

    def self.fetch_applicable_suggested_fix_alerts(repository:, alert_numbers:, head_commit_oid:, ref_names_bytes: nil)
      suggested_fixes_alerts = fetch_all_suggested_fix_alerts(repository:, alert_numbers:, head_commit_oid:, ref_names_bytes:).reject do |_, suggested_fix_alert|
        suggested_fix = suggested_fix_alert.suggested_fix
        suggested_fix.nil? || suggested_fix.outdated
      end

      raise CodeScanning::AutofixError.new(
        "No suggested #{'fix'.pluralize(alert_numbers.length)} found for #{'alert'.pluralize(alert_numbers.length)}",
        status: :unprocessable_entity
      ) if suggested_fixes_alerts.empty?

      suggested_fixes_alerts
    end

    def self.fetch_suggested_fix(repository:, alert_number:, head_commit_oid:, ref_names_bytes: nil)
      suggested_fix_alerts = fetch_applicable_suggested_fix_alerts(repository:, alert_numbers: [alert_number], head_commit_oid:, ref_names_bytes:)
      new(suggested_fix_alerts[alert_number].suggested_fix)
    end

    def diff_entries
      __getobj__.files.each_with_object([]) do |file, out|
        parser = GitHub::Diff::Parser.new(file.diff_content)
        parser.each do |entry|
          out << entry
        end
      end
    rescue GitHub::Diff::Parser::UnrecognizedText => err
      # report the error to Sentry
      Failbot.report!(err)
      []
    end
  end
end
