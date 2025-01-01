# typed: true
# frozen_string_literal: true

module Notifyd
  # RecipientsHelper class encapsulates the logic for determining the explicit recipients of a notification.
  # The explicit recipients may contain explicitly mentioned users or team members, commenters, author of the
  # thread etc. The logic of forming recipients depends on a subject and a trigger.
  class RecipientsHelper

    attr_reader :subject, :trigger, :previous_body, :current_body
    KNOWN_ACTIONS = %w(update create closed reopened converted_to_discussion).freeze

    # @param [Object] subject - the subject that produced Notification (Issue, Gist, PullRequest etc)
    # @param [String] trigger - the action that caused Notification (update, create, etc).
    # @param [String] previous_body - needed only for update operations and contains previous body of the subject.
    # @param [String] current_body - needed for operations that generate or update content.
    #
    # @return [Object] - instance of RecipientsHelper
    def initialize(subject, trigger, previous_body = nil, current_body = nil)
      @subject = subject
      @trigger = trigger
      @current_body = current_body
      @previous_body = previous_body
    end

    def explicit_recipients
      return [] unless KNOWN_ACTIONS.include?(trigger)
      reasons_to_recipients = Hash.new { |h, k| h[k] = [] }
      recipients_to_reasons.map do |user_id, reasons|
        # Temporary workaround to make sure that ignore settings are not appliced to mentions.
        # In order to achieve this we remove all other reasons except "mention" from the list for the mentioned user.
        # In this case we are not going to apply ignore settings that are created for comment, author and manual reasons
        # to the mentioned user. This way mentioned user will get notified even when they're unsubscribed.
        # TODO: we need to remove this workaround once we have a proper way to handle ignore settings for mentions.
        if reasons.include?("mention") && subject.notifications_thread.class.name == "Gist"
          reasons_to_recipients["mention"] << User.new(id: user_id)
          next
        end

        reasons.each do |reason|
          reasons_to_recipients[reason] << User.new(id: user_id)
        end
      end

      explicit_recipients = []
      reasons_to_recipients.each do |reason, users|
        explicit_recipients << {
          reason: reason,
          users: users
        }
      end

      explicit_recipients
    end

    private

    def recipients_to_reasons
      GitHub.tracer.in_span("recipients_to_reasons", kind: :internal) do |_span|
        result = mentionees
        result.merge!(team_mentionees) { |_key, val1, val2| val1 + val2 }
        return result if trigger == "update"
        result.merge!(author) { |_key, val1, val2| val1 + val2 }
        result.merge!(commenters) { |_key, val1, val2| val1 + val2 }
        result.merge!(memex_project_statuses) { |_key, val1, val2| val1 + val2 }
        result.merge!(assignees) { |_key, val1, val2| val1 + val2 }
        result.merge!(state_changees) { |_key, val1, val2| val1 + val2 }
        result
      end
    end

    def mentionees
      GitHub.tracer.in_span("mentionees", kind: :internal) do |_span|
        return {} unless current_body
        mentionees = Hash.new { |h, k| h[k] = [] }
        mention_diff.added_users.each do |user|
          mentionees[user.id] << "mention"
        end
        mentionees
      end
    end

    def team_mentionees
      GitHub.tracer.in_span("team_mentionees", kind: :internal) do |_span|
        return {} unless current_body
        return {} if subject.notifications_thread.class.name == "Gist"

        mentioned_teams = mention_diff.added_teams

        # A temporary measure to prevent `@epicgames/developers` from being notified
        # See https://github.com/github/platform-health-incidents/issues/486
        if FeatureFlag.vexi.enabled?(:dont_notify_epicgames_developers, default: true)
          mentioned_teams = mentioned_teams.reject { |team| team.id == Team::NewsiesAdapter::EPICGAMES_DEVELOPER_TEAM_ID }
        end

        mentioned_teams = mentioned_teams.reject { |team| team.notifications_disabled? }

        #adding a logger for production testing: check correct removal of mentioned teams with notifications disabled
        mentioned_teams.each do |mentioned_team|
          GitHub.logger.info("RecipientsHelper: this team is notified because it has notifications enabled", {
            "code.function": "remove_mentioned_teams_with_disabled_notifications",
            "gh.organization": mentioned_team.organization.display_login,
            "gh.team.name": mentioned_team.name,
            "gh.team.notification_setting": mentioned_team.notification_setting,
          })
        end

        mentionees = Hash.new { |h, k| h[k] = [] }
        mentioned_teams.each do |mentioned_team|
          subject.notifications_thread.subscribable_team_members(mentioned_team).each do |user|
            mentionees[user.id] << "team_mention"
          end
        end
        mentionees
      end
    end

    def author
      GitHub.tracer.in_span("author", kind: :internal) do |_span|
        return {} unless subject.notifications_thread.user_id
        { subject.notifications_thread.user_id => ["author"] }
      end
    end

    def commenters
      GitHub.tracer.in_span("commenters", kind: :internal) do |_span|
        commenters = Hash.new { |h, k| h[k] = [] }
        if subject.notifications_thread.respond_to?(:comments)
          subject.notifications_thread.comments.distinct.pluck(:user_id).each do |commenter_id|
            commenters[commenter_id] << "comment"
          end
        end

        commenters
      end
    end

    def memex_project_statuses
      GitHub.tracer.in_span("memex_project_statuses", kind: :internal) do |_span|
        commenters = Hash.new { |h, k| h[k] = [] }
        if subject.notifications_thread.respond_to?(:memex_project_statuses)
          subject.notifications_thread.memex_project_statuses.distinct.pluck(:creator_id).each do |commenter_id|
            commenters[commenter_id] << "state_change"
          end
        end

        commenters
      end
    end

    def assignees
      GitHub.tracer.in_span("assignees", kind: :internal) do |_span|
        assignees = Hash.new { |h, k| h[k] = [] }
        if subject.notifications_thread.respond_to?(:assignees)
          subject.notifications_thread.assignees.distinct.pluck(:id).each do |assignee_id|
            assignees[assignee_id] << "assign"
          end
        end

        assignees
      end
    end

    def state_changees
      GitHub.tracer.in_span("state_changees", kind: :internal) do |_span|
        changees = Hash.new { |h, k| h[k] = [] }
        if subject.notifications_thread.respond_to?(:events)
          subject.notifications_thread.events.where(event: %w(closed reopened converted_to_discussion)).distinct.pluck(:actor_id).each do |actor_id|
            changees[actor_id] << "state_change"
          end
        end

        changees
      end
    end

    def mention_diff
      @mention_diff ||= GitHub::MentionDiff.new(
        previous_body || "", # Empty for create operation
        current_body,
        subject.async_body_context.sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      )
    end
  end
end
