# typed: true
# frozen_string_literal: true

class UpdateSubscriptionsAndNotifyJob < ApplicationJob

  include Newsies::Reasons

  queue_as :subscribe_and_notify

  # Number of users we want to subscribe in single throttle block
  BATCH_SIZE = 10

  # Discard the job if the subject or author are deleted before the job runs
  discard_on ActiveRecord::RecordNotFound

  DATABASE_UNAVAILABLE_EXCEPTIONS = [
      Freno::Throttler::Error,
      *Resiliency::Response::UnavailableExceptions
    ]

  retry_on *DATABASE_UNAVAILABLE_EXCEPTIONS, wait: :polynomially_longer, attempts: 20

  retry_on_dirty_exit

  # Updates the mentioned subscribers for a given subject and its changed body.
  #
  # subject - A mentionable subject
  # previous_body - Array containing the old and new body
  # deliver_notifications - Boolean indicating whether notifications should be delivered
  # spam_check_delay_served - Boolean indicating whether the spam check delay has already been served.
  #
  # Returns nothing
  def perform(subject:, previous_body:, deliver_notifications:, spam_check_delay_served: false)
    old_text = previous_body.first
    new_text = previous_body.second
    body_context = subject.async_body_context.sync
    mention_diff_helper = GitHub::MentionDiff.new(old_text, new_text, body_context)

    modify_subscriptions(subject, mention_diff_helper)

    if deliver_notifications.nil? || deliver_notifications
      author_id = subject.user_id

      mention_user_ids = mention_ids_to_notify(author_id, mention_diff_helper)
      unless mention_user_ids.empty?
        GitHub.newsies.trigger(
          subject,
          recipient_ids: mention_user_ids,
          event_time: subject.updated_at,
          is_update: true,
          spam_check_delay_served: spam_check_delay_served,
        )
      end

      team_mention_user_ids = team_mention_ids_to_notify(author_id, mention_diff_helper)
      unless team_mention_user_ids.empty?
        GitHub.newsies.trigger(
          subject,
          recipient_ids: team_mention_user_ids,
          reason: "team-mentioned",
          event_time: subject.updated_at,
          is_update: true,
          spam_check_delay_served: spam_check_delay_served,
        )
      end
    end

    nil
  end

  private

  # Helper method to update subscriptions for a given subject after changing mentions.
  #
  # subject - A mentionable subject
  # mention_diff_helper - A GitHub::MentionDiff instance
  #
  # Returns an Array of user ids
  def modify_subscriptions(subject, mention_diff_helper)
    mention_diff_helper.added_users.each_slice(BATCH_SIZE) do |batched_users|
      with_write do
        Newsies::ThreadSubscription.throttle { subject.subscribe_mentioned(batched_users) }
      end
    end

    teams = mention_diff_helper.added_teams.uniq.compact

    # A temporary measure to prevent `@epicgames/developers` from being notified
    # See https://github.com/github/platform-health-incidents/issues/486
    if GitHub.flipper[:dont_notify_epicgames_developers].enabled?
      teams.reject! { |team| team.id == Team::NewsiesAdapter::EPICGAMES_DEVELOPER_TEAM_ID }
    end

    #Removes team from list to prevent team with notifications disabled from being notified
    teams = teams.reject { |team| team.notifications_disabled? }

    #adding a logger for production testing: check correct removal of mentioned teams with notifications disabled
    teams.each do |mentioned_team|
      GitHub.logger.info("UpdateSubscriptionsAndNotifyJob: this team is notified because it has notifications enabled", {
        "code.function": "remove_mentioned_teams_with_disabled_notifications",
        "gh.organization": mentioned_team.organization.display_login,
        "gh.team.name": mentioned_team.name,
        "gh.team.notification_setting": mentioned_team.notification_setting,
      })
    end

    subscribe_mentioned_teams(subject, teams)

    subject.unsubscribable_users(mention_diff_helper.removed_users).each_slice(BATCH_SIZE) do |batched_users|
      Newsies::ThreadSubscription.throttle do
        batched_users.each do |user|
          with_write do
            subject.unsubscribe(user)
          end
        end
      end
    end

    nil
  end

  # Subscribe a list of mentioned teams to the given subject.
  #
  # subject - The subscribale subject
  # mentions - Array of teams, or Team scope, that were mentioned.
  #
  # Returns nothing.
  def subscribe_mentioned_teams(subject, mentioned_teams)
    author = subject.respond_to?(:user) ? subject.user : nil
    return if author && author.spammy?

    notifications_thread = subject.notifications_thread
    mentioned_teams.each do |mentioned_team|
      team_members = notifications_thread.subscribable_team_members(mentioned_team)
      team_members.each_slice(BATCH_SIZE) do |batched_team_members|
        with_write do
          Newsies::ThreadSubscription.throttle do
            notifications_thread.subscribe_all(batched_team_members, "team-mentioned")
          end
        end
      end
    end

    nil
  end

  # Returns a list of user ids that should get notified because of a new mention.
  #
  # author_id - Id of the subject's author
  # mention_diff_helper - A GitHub::MentionDiff instance
  #
  # Returns an Array of user ids
  def mention_ids_to_notify(author_id, mention_diff_helper)
    mention_diff_helper.added_users.map(&:id) - [author_id]
  end

  # Returns a list of user ids that should get notified because of a new team mention.
  #
  # author_id - Id of the subject's author
  # mention_diff_helper - A GitHub::MentionDiff instance
  #
  # Returns an Array of user ids
  def team_mention_ids_to_notify(author_id, mention_diff_helper)
    added_team_mention_ids = mention_diff_helper.added_teams.map(&:id)
    member_ids_of_team_mentions = Team.members_of(added_team_mention_ids, immediate_only: false).pluck(:id)
    # We only want to consider mentioned members that haven't been mentioned
    ids_to_ignore = mention_diff_helper.added_users.map(&:id) + [author_id]

    member_ids_of_team_mentions - ids_to_ignore
  end
end
