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

      # We are not creating issues for campaigns created by spammy users
      return if campaign.spammy?

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
            create_issue(campaign, repo, bot, logging_stats)
          end
        end
      end

      GitHub.dogstats.distribution("security_campaign.issue.time_to_creation", Time.now - campaign.published_at)

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

    private

    sig do
      params(
        campaign: SecurityCampaigns::SecurityCampaign,
        repo: Repository,
        bot: User,
        logging_stats: T::Hash[Symbol, Integer]
      ).void
    end
    def create_issue(campaign, repo, bot, logging_stats)
      issue_builder = SecurityCampaigns::IssueBuilder.new(security_campaign: campaign, repository: repo)
      issue_domain = Issues.domain
      issue_attributes = Issues::CreateIssueAttributes.new(
        repository: repo,
        title: issue_builder.issue_title,
        body: issue_builder.issue_body
      )

      issue_result_object = GitHub.context.push(actor_id: bot.id) do
        issue_domain.create(issue_attributes, bot)
      end

      case issue_result_object
      when GH::Result::Ok
        issue = issue_result_object.value
        logging_stats[:issue_created] = T.must(logging_stats[:issue_created]) + 1
        begin
          SecurityCampaigns::SecurityCampaignIssue.create!(
            security_campaign: campaign,
            issue: issue,
            repository: repo,
          )
          GitHub.dogstats.increment("security_campaign.issue", tags: ["event:create", "status:success"])
        rescue ActiveRecord::RecordNotUnique => e
          GitHub.dogstats.increment("security_campaign.issue", tags: ["event:create", "status:error_record_not_unique"])
          logging_stats[:record_not_unique] = T.must(logging_stats[:record_not_unique]) + 1
          GitHub.logger.info(
            "ActiveRecord::RecordNotUnique error when creating security campaign issue",
            "gh.organization.id" => campaign.organization_id,
            "gh.security_campaign.id" => campaign.id,
            "gh.repository.id" => repo.id,
            "gh.issue.id" => issue.id,
          )
        end
      when GH::Result::Error
        GitHub.dogstats.increment("security_campaign.issue", tags: ["event:create", "status:error"])
        logging_stats[:errors] = T.must(logging_stats[:errors]) + 1
        GitHub.logger.info(
          "Security campaign automatic issue creation failed for",
          "gh.organization.id" => campaign.organization_id,
          "gh.security_campaign.id" => campaign.id,
          "gh.repository.id" => repo.id,
          "gh.security_campaign.issues.errors" => issue_result_object.message,
        )
      end
    end
  end
end
