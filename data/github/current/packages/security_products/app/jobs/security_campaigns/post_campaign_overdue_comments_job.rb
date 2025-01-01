# typed: strict
# frozen_string_literal: true

module SecurityCampaigns
  # This job is triggered when a security campaign becomes overdue
  # and posts a comment to all issues in repos that still have open alerts.
  class PostCampaignOverdueCommentsJob < ApplicationJob
    queue_as :security_campaigns

    retry_on_dirty_exit

    sig { params(campaign_id: Integer).void }
    def perform(campaign_id:)
      campaign = SecurityCampaigns::SecurityCampaign.find_by(id: campaign_id)
      if !campaign.present?
        GitHub.logger.info("Campaign not present", { campaign_id: })
        return
      end

      if campaign.draft?
        GitHub.logger.info("Campaign is in draft", { campaign_id: })
        return
      end

      org = campaign.organization
      if !org.present? || !SecurityCampaigns.issue_creation_enabled?(org)
        GitHub.logger.info("Campaign issues not enabled", { campaign_id: })
        return
      end

      if campaign.ends_at > DateTime.now
        GitHub.logger.info("Campaign not overdue", { campaign_id: })
        return
      end
      if campaign.closed?
        GitHub.logger.info("Campaign closed", { campaign_id: })
        return
      end

      bot = SecurityCampaigns.bot!

      # Find the open count for every repository in the campaign
      repo_counts_response = GitHub::Turboscan.counts_by_repo({
        owner_ids: [org.id],
        filter: {
          security_campaign_ids: [campaign.id],
        },
      })
      raise StandardError.new(repo_counts_response&.error&.msg || "No response when fetching alerts") if repo_counts_response.nil? || repo_counts_response.error.present?

      repo_counts_data = repo_counts_response.data
      raise StandardError.new("No data when fetching alerts") if repo_counts_data.nil?

      open_count_by_repo_id = repo_counts_data.repository_counts.map { |r| [r.repository_id, r.open_count] }.to_h

      campaign_issues = campaign.security_campaign_issues.includes(issue: :repository)

      # Uses batched queries and caches the archived status of each repository
      Promise.all(campaign_issues.map { |campaign_issue| campaign_issue.issue&.repository&.async_archived? }).sync

      logging_stats = {
        comments_created: 0,
        errors: 0,
        issue_deleted: 0,
        issue_closed: 0,
        repository_nil: 0,
        is_archived: 0,
        has_no_issues: 0,
        no_open_alerts: 0,
      }

      campaign_issues.each do |campaign_issue|
        # When the issue has been transferred to a different repository this method will
        # find the new issue and load it as well as the new repository, creating DB queries.
        # Otherwise it will just return the issue with preloaded information.
        issue = campaign_issue.issue_following_transfers

        if issue.nil?
          GitHub.dogstats.increment("security_campaign.issue.comment", tags: ["event:campaign_overdue", "status:skipped_issue_not_found"])
          logging_stats[:issue_deleted] += 1
          next
        end
        if issue.closed?
          GitHub.dogstats.increment("security_campaign.issue.comment", tags: ["event:campaign_overdue", "status:skipped_issue_closed"])
          logging_stats[:issue_closed] += 1
          next
        end

        if issue.repository.nil?
          GitHub.dogstats.increment("security_campaign.issue.comment", tags: ["event:campaign_overdue", "status:skipped_repo_not_found"])
          logging_stats[:repository_nil] += 1
          next
        end
        if issue.repository.archived?
          GitHub.dogstats.increment("security_campaign.issue.comment", tags: ["event:campaign_overdue", "status:skipped_repo_archived"])
          logging_stats[:is_archived] += 1
          next
        end
        if !issue.repository.has_issues?
          GitHub.dogstats.increment("security_campaign.issue.comment", tags: ["event:campaign_overdue", "status:skipped_repo_has_issues"])
          logging_stats[:has_no_issues] += 1
          next
        end

        open_count = open_count_by_repo_id[issue.repository_id]
        if open_count == 0
          GitHub.dogstats.increment("security_campaign.issue.comment", tags: ["event:campaign_overdue", "status:skipped_no_open_alerts"])
          logging_stats[:no_open_alerts] += 1
          next
        end

        comment_body = <<~MARKDOWN
          This campaign was due on #{campaign.ends_at.strftime("%b %-d, %Y")}. There #{"is".pluralize(open_count)} currently #{open_count} #{"open alert".pluralize(open_count)}.

          You can take action by:
          - mitigating the remaining vulnerabilities in the security campaign.
          - #{campaign.contact_link.nil? ? "" : "checking the contact link or "}asking a campaign manager to extend the due date.
        MARKDOWN

        with_write do
          comment = issue.create_comment(bot, comment_body)
          if !comment.persisted?
            error = comment.errors.map { |error| error.message }.join("\n")
            GitHub.logger.info("Error posting campaign overdue issue comment", { campaign_id:, repository_id: issue.repository_id, issue_id: issue.id, error: })
            GitHub.dogstats.increment("security_campaign.issue.comment", tags: ["event:campaign_overdue", "status:error"])
            logging_stats[:errors] += 1
          else
            issue_is_transferred = issue.repository_id != campaign_issue.repository_id
            GitHub.dogstats.increment("security_campaign.issue.comment", tags: ["event:campaign_overdue", "status:success", "transferred:#{issue_is_transferred}"])
            logging_stats[:comments_created] += 1
          end
        end
      end

      GitHub.logger.info(
        "Posted campaign overdue issue comments",
        "gh.organization.id" => campaign.organization_id,
        "gh.security_campaign.id" => campaign.id,
        "gh.security_campaign.issues.comments.comments_created" => logging_stats[:comments_created],
        "gh.security_campaign.issues.comments.errors" => logging_stats[:errors],
        "gh.security_campaign.issues.comments.issue_deleted" => logging_stats[:issue_deleted],
        "gh.security_campaign.issues.comments.issue_closed" => logging_stats[:issue_closed],
        "gh.security_campaign.issues.comments.repository_nil" => logging_stats[:repository_nil],
        "gh.security_campaign.issues.comments.archived_repos" => logging_stats[:is_archived],
        "gh.security_campaign.issues.comments.repos_without_issues" => logging_stats[:has_no_issues],
        "gh.security_campaign.issues.comments.no_open_alerts" => logging_stats[:no_open_alerts],
      )
    end
  end
end
