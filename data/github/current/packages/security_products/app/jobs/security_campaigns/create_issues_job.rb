# typed: strict
# frozen_string_literal: true

module SecurityCampaigns
  # This job is triggered when a security campaign is created and creates one issue per campaign and repository.
  class CreateIssuesJob < ApplicationJob
    queue_as :security_campaigns

    retry_on_dirty_exit

    sig { params(campaign_id: Integer, repository_ids: T::Array[Integer]).void }
    def perform(campaign_id:, repository_ids:)
      campaign = SecurityCampaigns::SecurityCampaign.published.find_by(id: campaign_id)
      if !campaign.present?
        GitHub.logger.info("Campaign not present", { campaign_id: })
        return
      end

      campaign_repos = Repository.where(id: repository_ids)

      bot = SecurityCampaigns.bot!

      GitHub.logger.info(
        "Security campaign automatic issue creation starting to create issues",
        "gh.organization.id" => campaign.organization_id,
        "gh.security_campaign.id" => campaign.id,
        "gh.repository.count" => campaign_repos.count,
      )

      logging_stats = Hash.new(0)

      campaign_repos.each do |repo|
        if !repo.has_issues?
          GitHub.dogstats.increment("security_campaign.issue", tags: ["event:create", "status:skipped_repo_has_issues"])
          logging_stats[:has_no_issues] += 1
        elsif repo.archived?
          GitHub.dogstats.increment("security_campaign.issue", tags: ["event:create", "status:skipped_repo_archived"])
          logging_stats[:is_archived] += 1
        elsif SecurityCampaigns::SecurityCampaignIssue.exists?(security_campaign: campaign, repository: repo)
          GitHub.dogstats.increment("security_campaign.issue", tags: ["event:create", "status:skipped_issue_already_exists"])
          logging_stats[:issue_already_exists] += 1
        else
          with_write do
            issue_builder = SecurityCampaigns::IssueBuilder.new(security_campaign: campaign, repository: repo)

            issue = Issue.new(user: bot, repository: repo, title: issue_builder.issue_title, body: issue_builder.issue_body)

            if issue.save
              logging_stats[:issue_created] += 1
              begin
                SecurityCampaigns::SecurityCampaignIssue.create!(
                  security_campaign: campaign,
                  issue: issue,
                  repository: repo,
                )
                GitHub.dogstats.increment("security_campaign.issue", tags: ["event:create", "status:success"])
              rescue ActiveRecord::RecordNotUnique => e
                GitHub.dogstats.increment("security_campaign.issue", tags: ["event:create", "status:error_record_not_unique"])
                logging_stats[:record_not_unique] += 1
                GitHub.logger.info(
                  "ActiveRecord::RecordNotUnique error when creating security campaign issue",
                  "gh.organization.id" => campaign.organization_id,
                  "gh.security_campaign.id" => campaign.id,
                  "gh.repository.id" => repo.id,
                  "gh.issue.id" => issue.id,
                )
              end
            else
              GitHub.dogstats.increment("security_campaign.issue", tags: ["event:create", "status:error"])
              logging_stats[:errors] += 1
              GitHub.logger.info(
                "Security campaign automatic issue creation failed for",
                "gh.organization.id" => campaign.organization_id,
                "gh.security_campaign.id" => campaign.id,
                "gh.repository.id" => repo.id,
                "gh.security_campaign.issues.errors" => issue.errors.full_messages,
              )
            end
          end
        end
      end

      GitHub.dogstats.timing("security_campaign.issue.time_to_creation", Time.now - campaign.published_at)

      GitHub.logger.info(
        "Security campaign automatic issue creation complete",
        "gh.organization.id" => campaign.organization_id,
        "gh.security_campaign.id" => campaign.id,
        "gh.security_campaign.issues.issues_created" => logging_stats[:issue_created],
        "gh.security_campaign.issues.errors" => logging_stats[:errors],
        "gh.security_campaign.issues.archived_repos" => logging_stats[:is_archived],
        "gh.security_campaign.issues.repos_without_issues" => logging_stats[:has_no_issues],
        "gh.security_campaign.issues.issue_already_exists" => logging_stats[:issue_already_exists],
        "gh.security_campaign.issues.record_not_unique" => logging_stats[:record_not_unique],
      )
    end
  end
end
