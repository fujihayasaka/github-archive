# typed: true
# frozen_string_literal: true

module CodeScanning
  class AutofixCommit
    def self.create(alert_number:, commit_message:, repository:, ref:, author:, suggested_fix:, reflog_via:, current_oid: nil)
      code_scanning_app = Apps::Privileged.integration(:code_scanning)
      raise "Code scanning integration not installed!" if code_scanning_app.nil?

      suggested_change = DiffEntrySuggestedChange.new(repository: repository, ref: ref, diff_entries: suggested_fix.diff_entries)

      suggested_change.commit_change_for_user(
        author: author,
        current_oid: current_oid || ref.commit.oid,
        message: commit_message || message_for_alert(alert_number:),
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

    def self.message_for_alert(alert_number:, alert_title: nil)
      title = "Potential fix for code scanning alert no. #{alert_number}"
      title += ": #{alert_title}" if alert_title.present?
      title
    end

    def self.message_for_alerts(alert_numbers:)
      "Potential fixes for #{alert_numbers.length} code scanning alerts"
    end

    sig do
      params(
        repository: Repository,
        alert_number: Integer,
        suggested_fix: T.untyped, # Sorbet doesn't recognize that CodeScanning::AutofixSuggestion has a description method
        security_campaign: T.nilable(SecurityCampaigns::SecurityCampaign),
      ).returns(String)
    end
    def self.pull_request_description_for_alert(repository:, alert_number:, suggested_fix:, security_campaign: nil)
      alert_link = alert_link(repository:, alert_number:)
      <<~MARKDOWN
        Potential fix for [#{alert_link}](#{alert_link})#{security_campaign ? " from the [#{security_campaign.name}](#{security_campaign_link(security_campaign)}) security campaign." : ""}

        #{suggested_fix.description}

        _Suggested fixes powered by Copilot Autofix. Review carefully before merging._
      MARKDOWN
    end

    sig do
      params(
        repository: Repository,
        alert_numbers: T::Array[Integer],
        suggested_fixes: T::Hash[Integer, Turboscan::Proto::SuggestedFix],
        security_campaign: T.nilable(SecurityCampaigns::SecurityCampaign),
      ).returns(String)
    end
    def self.pull_request_description_for_alerts(repository:, alert_numbers:, suggested_fixes:, security_campaign: nil)
      alerts_count = alert_numbers.length
      alert_descriptions = alert_numbers.map do |alert_number|
        alert_link = alert_link(repository:, alert_number:)
        description = suggested_fixes[alert_number]&.description

        if alerts_count < 4
          <<~MARKDOWN
            - #{alert_link}
            #{description&.gsub(/\n(?!\s)/, "\n  ")}
          MARKDOWN
        else
          <<~MARKDOWN
            - #{alert_link}
              <details>
                <summary>Suggested fix description</summary>
                #{description&.gsub(/\n(?!\s)/, "\n    ")}
              </details>
          MARKDOWN
        end
      end.join("\n\n")

      <<~MARKDOWN
        Potential fixes for #{alerts_count} code scanning alerts#{security_campaign ? " from the [#{security_campaign.name}](#{security_campaign_link(security_campaign)}) security campaign" : ""}:
        #{alert_descriptions}

        _Suggested fixes powered by Copilot Autofix. Review carefully before merging._
      MARKDOWN
    end

    def self.alert_link(repository:, alert_number:)
      UrlHelpers.repository_code_scanning_result_url(repository.owner, repository, number: alert_number, host: GitHub.url)
    end

    sig { params(security_campaign: SecurityCampaigns::SecurityCampaign).returns(String) }
    def self.security_campaign_link(security_campaign)
      UrlHelpers.security_center_security_campaign_url(org: security_campaign.organization, number: security_campaign.number, host: GitHub.url)
    end
  end
end
