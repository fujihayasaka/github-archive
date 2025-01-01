# typed: true
# frozen_string_literal: true

module Notifyd
  class ThreadSubscription
    include Notifyd::NetworkHelper
    include GitHub::Memoizer
    include Notifyd::Subscription

    attr_reader :user, :thread, :subscription, :mute_setting

    def initialize(user, thread, subscription, mute_setting)
      @user = user
      @thread = thread
      @subscription = subscription
      @mute_setting = mute_setting
    end

    def list
      nil
    end

    # Encapsulate a subscription-like participant activity
    #
    # We only care to know about the activity time and reason,
    # which is compared against other activities and subscriptions
    class ParticipantActivity
      attr_accessor :reason, :created_at

      def initialize(reason, created_at)
        @reason = reason
        @created_at = created_at.to_i
      end
    end

    memoize def oldest_participant_activity
      # Store list of candidate activities
      activities = []

      # Fetch author event
      if user.id == thread.user_id && thread.respond_to?(:created_at)
        activities << ParticipantActivity.new("author", thread.created_at)
      end

      # Fetch first user comment event if there is one
      if thread.respond_to?(:comments)
        comment = thread.comments.where(user_id: user.id).order(:created_at).limit(1).first
        if comment
          activities << ParticipantActivity.new("comment", comment.created_at)
        end
      end

      if thread.respond_to?(:memex_project_statuses)
        memex_project_status = thread.memex_project_statuses.order(:created_at).find_by(creator: user)

        if memex_project_status
          activities << ParticipantActivity.new("state_change", memex_project_status.created_at)
        end
      end

      # Fetch first assignee event if there is one
      if thread.respond_to?(:assignments)
        assignment = thread.assignments.where(assignee_id: user.id).order(:created_at).limit(1).first
        if assignment
          activities << ParticipantActivity.new("assign", assignment.created_at)
        end
      end

      # Fetch first issue event by user
      if thread.respond_to?(:events)
        event = thread.events.where(event: %w(closed reopened converted_to_discussion), actor_id: user.id).order(:created_at).limit(1).first
        if event
          activities << ParticipantActivity.new("state_change", event.created_at)
        end
      end

      # Out of all the candidates, return the first activity chronologically
      activities.sort { |a, b|  a.created_at <=> b.created_at }.first
    end

    def valid_subscription_exists?
      return false if subscription.nil?
      return false unless subscription.custom_fields.any?
      return false unless subscription.custom_fields.any? do |custom_field|
        custom_field.name == "thread_type"
      end
      return false unless subscription.custom_fields.any? do |custom_field|
        custom_field.name == "thread_id"
      end
      true
    end

    def user_is_participating?
      oldest_participant_activity.present?
    end

    def events_only?
      false
    end

    # Check whether this thread is ignored by the user or not
    def ignored?
      mute_setting.muted
    end

    # Public: Returns a Boolean specifying whether Subscriber is subscribed
    # and not ignored.
    def subscribed?
      (valid_subscription_exists? || user_is_participating?) && !ignored?
    end

    # Public: Returns a Boolean specifying whether the thread subscription object is valid
    # This object is valid if there is a subscription, the user is participating or they are ignoring the thread.
    def valid?
      valid_subscription_exists? || user_is_participating? || ignored?
    end

    def reason
      participant = oldest_participant_activity

      return "" unless subscribed?

      if participant.present? && subscription.present?
        # We want to show the original reason for the subscription, so we look for the oldest/earliest creation timestamp
        if participant.created_at < subscription.created_at
          participant.reason
        else
          subscription.reason
        end
      elsif participant.present?
        participant.reason
      elsif subscription.present?
        subscription.reason
      end
    end

    def created_at
      if ignored?
        timestamp = mute_setting.created_at
      else
        timestamp = [oldest_participant_activity, subscription].compact.map(&:created_at).min
      end

      return nil unless timestamp && timestamp > 0
      Time.at(timestamp)
    end
  end
end
