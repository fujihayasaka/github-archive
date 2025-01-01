# typed: strict
# frozen_string_literal: true

module SecurityCampaigns
  # This job is triggered when a security campaign is created and asks turboscan to create autofixes.
  class GenerateAutofixesJob < ApplicationJob
    queue_as :security_campaigns

    retry_on_dirty_exit

    # campaign_id - The security campaigns id
    # logical_alert_info - Array of [{repo_id:, alerts: [[alert_number: 1, tool_name: name], [alert_number: 2, tool_name: 2], []]}  entries
    sig { params(campaign_id: Integer, logical_alert_info: T::Array[{ repo_id: Integer, alerts: T::Array[{ alert_number: Integer, tool_name: String }] }]).void }
    def perform(campaign_id:, logical_alert_info:)
      campaign = SecurityCampaigns::SecurityCampaign.find_by(id: campaign_id)
      if !campaign.present?
        GitHub.logger.info("Campaign not present", { campaign_id: })
        return
      end

      org = T.must(campaign.organization)
      return unless CodeScanning::Autofix.any_enabled_for_org?(org)
      return unless SecurityCampaigns.autofix_generation_enabled?(org)

      logical_alert_info.map do |repo_hash|
        repo = Repositories::Public.find_active(repo_hash[:repo_id])
        unless repo
          GitHub.logger.info("Repo not present", { campaign_id:, repo_id: repo_hash[:repo_id] })
          next
        end
        next unless CodeScanning::Autofix.any_enabled_for_repo?(repo)

        default_ref = repo.default_branch_ref

        if default_ref.nil?
          GitHub.dogstats.increment("security_campaigns.suggested_fix.no_default_branch")
          next
        end

        # Filter out alerts that have tools that are not supported
        alert_numbers = repo_hash[:alerts].filter_map do |alert|
          next unless CodeScanning::Autofix.enabled_for_tool?(repo, alert[:tool_name])
          alert[:alert_number]
        end

        next if alert_numbers.empty?

        GitHub::Turboscan::SuggestedFixes.generate_suggested_fix(
          user_id: org.id,
          repository_id: repo_hash[:repo_id],
          alert_numbers:,
          ref_names_bytes: Array(default_ref.qualified_name.b),
          source: :SUGGESTED_FIX_SOURCE_SECURITY_CAMPAIGN,
          security_campaign_id: campaign.id,
        )
      end

      SecurityCampaigns::AutofixStateCheckJob.set(wait: 1.hour).perform_later(campaign_id: campaign.id)
    end
  end
end
