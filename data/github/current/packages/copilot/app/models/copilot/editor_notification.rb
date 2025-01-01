# typed: strict
# frozen_string_literal: true

module Copilot
  class EditorNotification < ApplicationRecord::Copilot
    include Copilot::Metrics
    extend T::Sig
    include ::Instrumentation::Model

    # These are all of the notifications that are sent in a 200/Success Response
    COPILOT_NOTIFICATION_TYPES = T.let({
      subscription_ending: "Subscription Ending",
      subscription_trial_ended: "Subscription Trial Ended",
      subscription_trial_ending: "Subscription Trial Ending",
      copilot_enterprise_seat_added: "Copilot Enterprise Seat Added",
      copilot_seat_added: "Copilot Seat Added",
      copilot_seat_removed: "Copilot Seat Removed",
      cfb_free_trial_ended: "Copilot Business Free Trial Ended",
      cfb_free_trial_welcome: "Copilot Business Free Trial Started",
      codespaces_demo_welcome: "Codespaces Demo Welcome",
      copilot_abuse_warning: "Copilot Abuse Warning",
    }.freeze, T::Hash[Symbol, String])

    self.table_name = "copilot_ide_notifications"
    self.strict_loading_by_default = true

    belongs_to :user, class_name: "::User", strict_loading: false

    validates :user, presence: true
    validates :notification_id, presence: true
    scope :by_type, ->(type) { where(notification_id: type) }
    scope :unacknowledged, -> { where(acknowledged_at: nil) }

    validate :correct_notification_id

    sig { params(user: ::User, notification_id: String, owner: T.nilable(T.any(::Organization, ::Business))).void }
    def self.create_for_user(user, notification_id, owner)
      copilot_user = Copilot::User.new(user)

      return if Copilot.copilot_object(owner).copilot_communication_opt_out? if owner.present?

      return if copilot_user.copilot_communication_opt_out?

      bindings = {
        user_id: user.id,
        notification_id: notification_id,
      }

      # The copilot_ide_notifications table has a unique index on (user_id, notification_id)
      # When we "create" a new notification, it starts out as unacknowledged (acknowledged_at is nil)
      query = Arel.sql(<<-SQL, **bindings)
        INSERT INTO copilot_ide_notifications (
          user_id,
          notification_id,
          created_at,
          updated_at
        ) VALUES (
          :user_id,
          :notification_id,
          NOW(),
          NOW()
        ) ON DUPLICATE KEY UPDATE
          acknowledged_at = NULL,
          updated_at = NOW()
      SQL

      ActiveRecord::Base.connected_to(role: :writing) do
        self.connection.insert(query)
      end
    end

    sig { void }
    def correct_notification_id
      return unless notification_id.present?

      return if COPILOT_NOTIFICATION_TYPES.keys.map(&:to_s).include?(notification_id)

      return if notification_id.match(/copilot_enterprise_seat_added_\d+/)
      return if notification_id.match(/copilot_seat_added_\d+/)
      return if notification_id.match(/copilot_seat_removed_\d+/)
      return if notification_id.match(/cfb_free_trial_ended_\d+/)
      return if notification_id.match(/cfb_free_trial_welcome_\d+/)
      return if notification_id.match(/codespaces_demo_\d+/)
      return if notification_id.match(/copilot_abuse_warning/)

      errors.add(:notification_id, "must be a valid notification type")
    end

    # Whether this notification has been acknowledged by the user
    sig { returns(T::Boolean) }
    def acknowledged?
      acknowledged_at.present?
    end

    # Acknowledge this notification
    sig { returns(T::Boolean) }
    def acknowledge
      update_attribute(:acknowledged_at, Time.now)
    end

    sig { returns(String) }
    def friendly_name
      if found = COPILOT_NOTIFICATION_TYPES[notification_id.to_sym]
        return found
      end

      case notification_id
      when /copilot_enterprise_seat_added_(\d+)/
        seat_id = $1
        seat = Copilot::Seat.find_by(id: seat_id)
        if seat
          "Copilot Enterprise Seat Added for #{seat.owner}"
        else
          "Copilot Enterprise Seat Added (Seat ID: #{$1})"
        end
      when /copilot_seat_added_(\d+)/
        name = "Copilot Seat Added"
        seat_id = $1
        seat = Copilot::Seat.find_by(id: seat_id)
        if seat && seat.owner
          "#{name} for #{seat.owner}"
        else
          seat_history = Copilot::SeatHistory.find_by(seat_id: seat_id)
          if seat_history && seat_history.owner
            "#{name} for #{seat_history.owner}"
          else
            "#{name} (Seat ID: #{seat_id})"
          end
        end
      when /copilot_seat_removed_(\d+)/
        owner_id = $1
        seat_history = Copilot::SeatHistory.find_by(owner_id: owner_id, assigned_user_id: user_id)
        if seat_history && seat_history.owner
          "Copilot Seat Removed for #{seat_history.owner}"
        else
          "Copilot Seat Removed (Organization ID: #{owner_id})"
        end
      else
        notification_id
          .titleize
          .gsub(/\s?\d+\z/, "")
          .gsub(" To ", " to ")
      end
    end

    sig { returns(T.nilable(Integer)) }
    def to_i
      id
    end
  end
end
