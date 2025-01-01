# typed: strict
# frozen_string_literal: true

module SecurityCampaigns
  # This job is triggered when a security campaign is closed
  # and posts a comment to all issues linked to the campaign.
  class PostCampaignClosedCommentsJob < ApplicationJob
    queue_as :security_campaigns

    retry_on_dirty_exit

    sig { params(campaign_id: Integer, actor_id: Integer).void }
    def perform(campaign_id:, actor_id:)
      campaign = SecurityCampaigns::SecurityCampaign.published.find_by(id: campaign_id)
      if !campaign.present?
        GitHub.logger.info("Campaign not present", { campaign_id: })
        return
      end

      org = campaign.organization
      if !org.present? || !SecurityCampaigns.issue_creation_enabled?(org)
        GitHub.logger.info("Campaign issue comments not enabled", { campaign_id: })
        return
      end

      bot = SecurityCampaigns.bot!

      # The actor might be nil if the user has been deleted
      # in the short time between the campaign being closed and this job running.
      # But in this case we can still continue and post the comment.
      actor = User.find_by(id: actor_id)

      campaign_issues = campaign.security_campaign_issues.includes(issue: :repository)

      # Uses batched queries and caches the archived status of each repository
      Promise.all(campaign_issues.map { |campaign_issue| campaign_issue.issue&.repository&.async_archived? }).sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)

      comment_body = <<~MARKDOWN
        The security campaign has been closed#{actor.nil? ? "" : " by [@#{actor.display_login}](#{UrlHelpers.user_url(actor, host: GitHub.url)})"}.

        #{campaign.contact_link.nil? ? "Reach" : "Check the contact link or reach"} out to a campaign manager for more information.
      MARKDOWN

      logging_stats = {
        comments_created: 0,
        errors: 0,
        issue_deleted: 0,
        issue_closed: 0,
        repository_nil: 0,
        is_archived: 0,
        has_no_issues: 0,
      }

      campaign_issues.each do |campaign_issue|
        # When the issue has been transferred to a different repository this method will
        # find the new issue and load it as well as the new repository, creating DB queries.
        # Otherwise it will just return the issue with preloaded information.
        issue = campaign_issue.issue_following_transfers

        if issue.nil?
          GitHub.dogstats.increment("security_campaign.issue.comment", tags: ["event:campaign_closed", "status:skipped_issue_not_found"])
          logging_stats[:issue_deleted] += 1
          next
        end
        if issue.closed?
          GitHub.dogstats.increment("security_campaign.issue.comment", tags: ["event:campaign_closed", "status:skipped_issue_closed"])
          logging_stats[:issue_closed] += 1
          next
        end

        if issue.repository.nil?
          GitHub.dogstats.increment("security_campaign.issue.comment", tags: ["event:campaign_closed", "status:skipped_repo_not_found"])
          logging_stats[:repository_nil] += 1
          next
        end
        if issue.repository.archived?
          GitHub.dogstats.increment("security_campaign.issue.comment", tags: ["event:campaign_closed", "status:skipped_repo_archived"])
          logging_stats[:is_archived] += 1
          next
        end
        if !issue.repository.has_issues?
          GitHub.dogstats.increment("security_campaign.issue.comment", tags: ["event:campaign_closed", "status:skipped_repo_has_issues"])
          logging_stats[:has_no_issues] += 1
          next
        end

        with_write do
          comment = issue.create_comment(bot, comment_body)
          if !comment.persisted?
            error = comment.errors.map { |error| error.message }.join("\n")
            GitHub.logger.info("Error posting campaign closed issue comment", { campaign_id:, repository_id: issue.repository_id, issue_id: issue.id, error: })
            GitHub.dogstats.increment("security_campaign.issue.comment", tags: ["event:campaign_closed", "status:error"])
            logging_stats[:errors] += 1
          else
            issue_is_transferred = issue.repository_id != campaign_issue.repository_id
            GitHub.dogstats.increment("security_campaign.issue.comment", tags: ["event:campaign_closed", "status:success", "transferred:#{issue_is_transferred}"])
            logging_stats[:comments_created] += 1
          end
        end
      end

      GitHub.logger.info(
        "Posted campaign closed issue comments",
        "gh.organization.id" => campaign.organization_id,
        "gh.security_campaign.id" => campaign.id,
        "gh.security_campaign.issues.comments.comments_created" => logging_stats[:comments_created],
        "gh.security_campaign.issues.comments.errors" => logging_stats[:errors],
        "gh.security_campaign.issues.comments.issue_deleted" => logging_stats[:issue_deleted],
        "gh.security_campaign.issues.comments.issue_closed" => logging_stats[:issue_closed],
        "gh.security_campaign.issues.comments.repository_nil" => logging_stats[:repository_nil],
        "gh.security_campaign.issues.comments.archived_repos" => logging_stats[:is_archived],
        "gh.security_campaign.issues.comments.repos_without_issues" => logging_stats[:has_no_issues],
      )
    end
  end
end
