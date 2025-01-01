# typed: strict
# frozen_string_literal: true

module SecurityCampaigns
  # This job is triggered when a security campaign is deleted
  # and posts a comment to all issues linked to the campaign.
  # Importantly, this job will run after the campaign has already been deleted,
  # so we have to rely on info that has been passed into the job and can't fetch new info about the campaign.
  class PostCampaignDeletedCommentsJob < ApplicationJob
    queue_as :security_campaigns

    retry_on_dirty_exit

    sig { params(deleted_campaign_id: Integer, org_id: Integer, issue_ids: T::Array[Integer], actor_id: Integer, contact_link_present: T::Boolean).void }
    def perform(deleted_campaign_id:, org_id:, issue_ids:, actor_id:, contact_link_present:)
      org = Organization.find_by(id: org_id)
      if !org.present? || !SecurityCampaigns.issue_creation_enabled?(org)
        GitHub.logger.info("Campaign issue comments not enabled", { org_id: })
        return
      end

      bot = SecurityCampaigns.bot!

      # The actor might be nil if the user has been deleted
      # in the short time between the campaign being closed and this job running.
      # But in this case we can still continue and post the comment.
      actor = User.find_by(id: actor_id)

      issues = Issue.where(id: issue_ids).includes(:repository)

      # Uses batched queries and caches the archived status of each repository
      Promise.all(issues.map { |issue| issue.repository&.async_archived? }).sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)

      comment_body = <<~MARKDOWN
        The security campaign has been deleted#{actor.nil? ? "" : " by [@#{actor.display_login}](#{UrlHelpers.user_url(actor, host: GitHub.url)})"}.

        #{contact_link_present ? "Check the contact link or reach" : "Reach" } out to a campaign manager for more information.
      MARKDOWN

      logging_stats = {
        comments_created: 0,
        errors: 0,
        issue_closed: 0,
        repository_nil: 0,
        is_archived: 0,
        has_no_issues: 0,
      }

      issues.each do |issue|
        if issue.closed?
          GitHub.dogstats.increment("security_campaign.issue.comment", tags: ["event:campaign_deleted", "status:skipped_issue_closed"])
          logging_stats[:issue_closed] += 1
          next
        end

        if issue.repository.nil?
          GitHub.dogstats.increment("security_campaign.issue.comment", tags: ["event:campaign_deleted", "status:skipped_repo_not_found"])
          logging_stats[:repository_nil] += 1
          next
        end
        if issue.repository.archived?
          GitHub.dogstats.increment("security_campaign.issue.comment", tags: ["event:campaign_deleted", "status:skipped_repo_archived"])
          logging_stats[:is_archived] += 1
          next
        end
        if !issue.repository.has_issues?
          GitHub.dogstats.increment("security_campaign.issue.comment", tags: ["event:campaign_deleted", "status:skipped_repo_has_issues"])
          logging_stats[:has_no_issues] += 1
          next
        end

        with_write do
          comment = issue.create_comment(bot, comment_body)
          if !comment.persisted?
            error = comment.errors.map { |error| error.message }.join("\n")
            GitHub.logger.info("Error posting campaign deleted issue comment", { repository_id: issue.repository_id, issue_id: issue.id, error: })
            GitHub.dogstats.increment("security_campaign.issue.comment", tags: ["event:campaign_deleted", "status:error"])
            logging_stats[:errors] += 1
          else
            GitHub.dogstats.increment("security_campaign.issue.comment", tags: ["event:campaign_deleted", "status:success"])
            logging_stats[:comments_created] += 1
          end
        end
      end

      GitHub.logger.info(
        "Posted campaign deleted issue comments",
        "gh.organization.id" => org_id,
        "gh.security_campaign.id" => deleted_campaign_id,
        "gh.security_campaign.issues.comments.comments_created" => logging_stats[:comments_created],
        "gh.security_campaign.issues.comments.errors" => logging_stats[:errors],
        "gh.security_campaign.issues.comments.issue_closed" => logging_stats[:issue_closed],
        "gh.security_campaign.issues.comments.repository_nil" => logging_stats[:repository_nil],
        "gh.security_campaign.issues.comments.archived_repos" => logging_stats[:is_archived],
        "gh.security_campaign.issues.comments.repos_without_issues" => logging_stats[:has_no_issues],
      )
    end
  end
end
