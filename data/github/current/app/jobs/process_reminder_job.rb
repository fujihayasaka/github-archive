# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class ProcessReminderJob < ApplicationJob
  queue_as :reminders

  locked_by timeout: 30.minutes, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC # Lock on all arguments

  resolve_tenant_context do |reminder|
    if reminder.is_a?(PersonalReminder)
      reminder.user&.enterprise_managed_business
    else
      reminder&.remindable&.business
    end
  end

  # These two limits may seem arbitrary, but they are to prevent an unbounded Slack message storm (which we encountered).
  # Right now, all scheduled reminders going to Slack end up as separate messages on a per repository basis.
  # That's due to the existing permission scheme for Hook::Event. Right now it's User, Org, or Repo.
  #
  # The REPOSITORY_LIMIT means that no more than 5 Slack messages will be posted at a given time (for a given organization).
  #
  # The NOTIFICATION_LIMIT means that WITHIN one of those 5 chosen Repositories, we won't create a massive message, if there were
  # 100s of pull requests that match.
  REPOSITORY_LIMIT = 5
  NOTIFICATION_LIMIT = 20
  TYPE_DELETED = "deleted"
  # Process given reminder.
  #
  # @param reminder [Reminder or PersonalReminder] record to process
  # @param delivery_target: [Time] the time the reminder is expected to be delivered
  # @param test: [Boolean] tests the job by sending the reminder, but not updating the next delivery time
  def perform(reminder, delivery_target:, test: false)
    unless test
      if !reminder.valid_delivery_at?(delivery_target)
        GitHub.dogstats.increment("reminders.stale_delivery_target")
        return
      end

      with_write { reminder.update_next_delivery_times }
    end

    unless reminder.has_valid_associations?
      return
    end

    if reminder.user && GitHub.flipper[:scheduled_reminders_teams_parity].enabled?(reminder.user) && !reminder.remindable.find_direct_or_team_member_by_login(reminder.user.login)
      # for MSTeams org wide reminders, all org users are allowed to create a reminder
      # we should delete the reminder if the user is no longer a member of the org
      # The associated  repo_ids will be null once the user is removed from org
      # picking a random repo ( which ms teams integration can access) to create the reminder event and then destroy.
      personal_reminder = reminder.is_a?(PersonalReminder)
      if !personal_reminder && reminder.slack_workspace&.type == "ReminderTeamsWorkspace"
        ms_teams_app = GitHub.msteams_github_app
        repo = ms_teams_app&.installations_on(reminder.remindable)&.first&.repositories&.first
        with_write do
          if repo
            reminder.set_repository_id_for_reminder_to_delete(repo.id)
            reminder.destroy
          end
        end
        return
      end
    end

    results = reminder.filtered_pull_requests

    prs_by_repo_id = results.prs_for_review.group_by(&:repository_id)
    prs_for_author_by_repo_id = results.prs_for_author.group_by(&:repository_id)
    repo_ids = (prs_by_repo_id.keys + prs_for_author_by_repo_id.keys).uniq

    if updated_limits_enabled?(reminder)
      repo_ids.each.with_index do |repo_id|
        Hook::Event::ReminderEvent.queue(
          event_at: delivery_target,
          pull_request_ids: (prs_by_repo_id[repo_id] || []).map(&:id),
          pull_request_ids_for_author: (prs_for_author_by_repo_id[repo_id] || []).map(&:id),
          reminder: reminder,
          repository_id: repo_id,
        )
      end
    else
      repo_ids.each.with_index do |repo_id, index|
        break if index > REPOSITORY_LIMIT - 1

        pull_request_ids = (prs_by_repo_id[repo_id] || []).map(&:id)[0...NOTIFICATION_LIMIT]
        pull_request_ids_for_author = (prs_for_author_by_repo_id[repo_id] || []).map(&:id)[0...NOTIFICATION_LIMIT]

        Hook::Event::ReminderEvent.queue(
          event_at: delivery_target,
          pull_request_ids: pull_request_ids,
          pull_request_ids_for_author: pull_request_ids_for_author,
          reminder: reminder,
          repository_id: repo_id,
        )
      end
    end
  end

  def updated_limits_enabled?(reminder)
    FeatureFlag.vexi.enabled?("scheduled_reminders_updated_limits", reminder.user, default: false)
  end
end
