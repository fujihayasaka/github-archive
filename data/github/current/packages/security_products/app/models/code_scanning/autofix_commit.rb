# typed: true
# frozen_string_literal: true

module CodeScanning
  class AutofixCommit
    def self.create(alert_number:, commit_message:, repository:, ref:, author:, suggested_fix:, reflog_via:)
      code_scanning_app = Apps::Privileged.integration(:code_scanning)
      raise "Code scanning integration not installed!" if code_scanning_app.nil?

      suggested_change = DiffEntrySuggestedChange.new(repository: repository, ref: ref, diff_entries: suggested_fix.diff_entries)

      suggested_change.commit_change_for_user(
        author: author,
        current_oid: ref.commit.oid,
        message: commit_message || "Fix code scanning alert no. #{alert_number}",
        sign: true,
        co_author_note: "Co-authored-by: Copilot Autofix powered by AI <#{code_scanning_app.bot.git_author_email}>",
        reflog_data: {
          repo_name: suggested_change.repository.name_with_display_owner,
          repo_public: suggested_change.repository.public?,
          user_login: code_scanning_app.bot.display_login,
          from: GitHub.context[:from],
          via: reflog_via || "code scanning suggested fix"
        }
      )
    end

    def self.pr_title(alert_number:, alert_title:)
      "Fix code scanning alert no. #{alert_number}: #{alert_title}"
    end

    def self.pull_request_description(alert_link, suggested_fix_description)
      <<~MARKDOWN
        Fixes [#{alert_link}](#{alert_link})

        #{suggested_fix_description}

        _Suggested fixes powered by Copilot Autofix. Review carefully before merging._
      MARKDOWN
    end
  end
end
