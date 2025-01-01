# typed: strict
# frozen_string_literal: true

module SecurityCampaigns
  # This job is triggered when a security campaign is updated and overwrites existing issue titles and bodies.
  class UpdateIssuesJob < ApplicationJob
    queue_as :security_campaigns

    retry_on_dirty_exit

    sig { params(campaign_id: Integer).void }
    def perform(campaign_id:)
      campaign = SecurityCampaigns::SecurityCampaign.published.find_by(id: campaign_id)
      if !campaign.present?
        GitHub.logger.info("Campaign not present", { campaign_id: })
        return
      end

      return unless SecurityCampaigns.issue_creation_enabled?(T.must(campaign.organization))

      campaign_issues = campaign.security_campaign_issues.includes(:repository, issue: :repository)

      # Uses batched queries and caches the archived status of each repository
      Promise.all(campaign_issues.map { |campaign_issue| campaign_issue.issue&.repository&.async_archived? }).sync

      bot = SecurityCampaigns.bot!

      GitHub.logger.info(
        "Security campaign automatic issue update starting to update issues",
        "gh.organization.id" => campaign.organization_id,
        "gh.security_campaign.id" => campaign.id,
        "gh.security_campaign.issues.count" => campaign_issues.count,
      )

      logging_stats = Hash.new(0)
      issue_domain = Issues.domain

      campaign_issues.each do |campaign_issue|
        # The repo that the issue was originally created in.
        # Be aware that the issue may have been transferred to a new repo since it was created.
        original_repo = campaign_issue.repository

        if original_repo.nil?
          GitHub.dogstats.increment("security_campaign.issue", tags: ["event:update", "status:skipped_repo_not_found"])
          logging_stats[:original_repo_deleted] += 1
          next
        end

        # When the issue has been transferred to a different repository this method will
        # find the new issue and load it as well as the new repository, creating DB queries.
        # Otherwise it will just return the issue with preloaded information.
        issue = campaign_issue.issue_following_transfers

        if issue.nil?
          GitHub.dogstats.increment("security_campaign.issue", tags: ["event:update", "status:skipped_issue_not_found"])
          logging_stats[:issue_deleted] += 1
        elsif !issue.repository.has_issues?
          GitHub.dogstats.increment("security_campaign.issue", tags: ["event:update", "status:skipped_repo_has_issues"])
          logging_stats[:has_no_issues] += 1
        elsif issue.repository.archived?
          GitHub.dogstats.increment("security_campaign.issue", tags: ["event:update", "status:skipped_repo_archived"])
          logging_stats[:is_archived] += 1
        else
          with_write do
            issue_result_object = GitHub.context.push(actor_id: bot.id) do
              issue_builder = SecurityCampaigns::IssueBuilder.new(security_campaign: campaign, repository: original_repo)
              issue_attributes = Issues::UpdateIssueAttributes.new(title: issue_builder.issue_title, body: issue_builder.updated_issue_body(T.must(bot.integration).name))

              issue_domain.update(issue, issue_attributes, bot)
            end

            case issue_result_object
            when GH::Result::Ok
              issue_is_transferred = issue.repository_id != original_repo.id
              GitHub.dogstats.increment("security_campaign.issue", tags: ["event:update", "status:success", "transferred:#{issue_is_transferred}"])
              logging_stats[:issues_updated] += 1
            when GH::Result::Error
              GitHub.dogstats.increment("security_campaign.issue", tags: ["event:update", "status:error"])
              logging_stats[:errors] += 1
              GitHub.logger.info(
                "Security campaign automatic issue update failed for",
                "gh.organization.id" => campaign.organization_id,
                "gh.security_campaign.id" => campaign.id,
                "gh.repository.id" => issue.repository_id,
                "gh.issue.id" => issue.id,
                "gh.security_campaign.issues.errors" => issue_result_object.message,
              )
            end
          end
        end
      end

      GitHub.logger.info(
        "Security campaign automatic issue update complete",
        "gh.organization.id" => campaign.organization_id,
        "gh.security_campaign.id" => campaign.id,
        "gh.security_campaign.issues.issues_updated" => logging_stats[:issues_updated],
        "gh.security_campaign.issues.errors" => logging_stats[:errors],
        "gh.security_campaign.issues.archived_repos" => logging_stats[:is_archived],
        "gh.security_campaign.issues.issue_deleted" => logging_stats[:issue_deleted],
        "gh.security_campaign.issues.original_repo_deleted" => logging_stats[:original_repo_deleted],
        "gh.security_campaign.issues.repos_without_issues" => logging_stats[:has_no_issues],
      )
    end
  end
end
