# typed: strict
# frozen_string_literal: true

require "google/protobuf/wrappers_pb"
require "hydro/schemas/github/copilot/v0/content_safety_monitoring_state_change_pb"

module CopilotContentSafety
  class MonitoredUser < ApplicationRecord::Copilot
    HYDRO_SCHEMA = "github.copilot.v0.ContentSafetyMonitoringStateChange"
    HYDRO_SCHEMA_TOKEN_REVOCATION = "hydro.schemas.copilot.v1.TokenRevocation"
    HYDRO_INITIATOR_TYPE = Hydro::Schemas::Github::Copilot::V0::ContentSafetyMonitoringStateChange::InitiatorType
    HYDRO_MONITORING_STATE = Hydro::Schemas::Github::Copilot::V0::ContentSafetyMonitoringStateChange::MonitoringState

    self.table_name = "copilot_monitored_users"
    self.strict_loading_by_default = true

    belongs_to :user, class_name: "::User", inverse_of: :copilot_monitored_user, strict_loading: false # rubocop:disable GitHub/UseBelongsToDomain

    validates :user, presence: true

    delete_in_background_with :user

    sig do
      params(
        user: ::User,
        monitored: T::Boolean,
        actor: T.nilable(::User),
        initiator_type: Symbol,
        reason: String,
        chat_turn_scan_event_id: T.nilable(String),
        session_id: T.nilable(String),
      ).returns(Time)
    end
    def self.set_monitoring_state!(
      user:,
      monitored:,
      actor: nil,
      initiator_type: :INITIATOR_TYPE_UNKNOWN,
      reason: "",
      chat_turn_scan_event_id: nil,
      session_id: nil
    )
      if monitored
        monitor!(
          user,
          actor: actor,
          initiator_type: initiator_type,
          reason: reason,
          chat_turn_scan_event_id: chat_turn_scan_event_id,
          session_id: session_id,
        )
      else
        unmonitor!(
          user,
          actor: actor,
          initiator_type: initiator_type,
          reason: reason,
          chat_turn_scan_event_id: chat_turn_scan_event_id,
          session_id: session_id,
        )
      end
    end

    sig { params(user: ::User).returns(T::Boolean) }
    def self.monitored?(user)
      exists?(user_id: user.id)
    end

    sig do
      params(
        user: ::User,
        actor: T.nilable(::User),
        initiator_type: Symbol,
        reason: String,
        chat_turn_scan_event_id: T.nilable(String),
        session_id: T.nilable(String),
      ).returns(Time)
    end
    def self.monitor!(
      user,
      actor: nil,
      initiator_type: :INITIATOR_TYPE_UNKNOWN,
      reason: "",
      chat_turn_scan_event_id: nil,
      session_id: nil
    )
      monitored_user = create_or_find_by!(user: user)

      if monitored_user.previously_new_record?
        publish_monitoring_state_change_event(
          account: user,
          actor: actor,
          initiator_type: initiator_type,
          state: :MONITORING_ENABLED,
          reason: reason,
          chat_turn_scan_event_id: chat_turn_scan_event_id,
          session_id: session_id,
        )

        publish_token_revocation_event(user: user)
      end

      monitored_user.updated_at
    end

    sig do
      params(
        user: ::User,
        actor: T.nilable(::User),
        initiator_type: Symbol,
        reason: String,
        chat_turn_scan_event_id: T.nilable(String),
        session_id: T.nilable(String),
      ).returns(Time)
    end
    def self.unmonitor!(
      user,
      actor: nil,
      initiator_type: :INITIATOR_TYPE_UNKNOWN,
      reason: "",
      chat_turn_scan_event_id: nil,
      session_id: nil
    )
      where(user: user).find_each do |monitored_user|
        monitored_user.destroy!

        publish_monitoring_state_change_event(
          account: user,
          actor: actor,
          initiator_type: initiator_type,
          state: :MONITORING_DISABLED,
          reason: reason,
          chat_turn_scan_event_id: chat_turn_scan_event_id,
          session_id: session_id,
        )

        publish_token_revocation_event(user: user)
      end

      Time.current
    end

    private

    sig do
      params(
        account: ::User,
        actor: T.nilable(::User),
        initiator_type: Symbol,
        state: Symbol,
        reason: String,
        chat_turn_scan_event_id: T.nilable(String),
        session_id: T.nilable(String),
      ).void
    end
    def self.publish_monitoring_state_change_event(
      account:,
      actor:,
      initiator_type:,
      state:,
      reason:,
      chat_turn_scan_event_id:,
      session_id:
    )
      message = {
        account: Hydro::EntitySerializer.user(account),
        initiator_type: Hydro::EntitySerializer.enum(
          type: HYDRO_INITIATOR_TYPE,
          value: actor.nil? && initiator_type == :STAFF ? :INITIATOR_TYPE_UNKNOWN : initiator_type,
          default: :INITIATOR_TYPE_UNKNOWN,
        ),
        state: Hydro::EntitySerializer.enum(
          type: HYDRO_MONITORING_STATE,
          value: state,
          default: :MONITORING_STATE_UNKNOWN,
        ),
        reason: reason.to_s,
      }

      if actor.present?
        message[:actor] = Hydro::EntitySerializer.user(actor)
      end

      if chat_turn_scan_event_id.present?
        message[:chat_turn_scan_event_id] = chat_turn_scan_event_id
      end

      if session_id.present?
        message[:session_id] = session_id
      end

      ActiveRecord.after_all_transactions_commit do
        GitHub.hydro_publisher.publish(
          message,
          schema: HYDRO_SCHEMA,
        )
      end
    end

    sig { params(user: ::User).void }
    def self.publish_token_revocation_event(user:)
      tracking_id = user.analytics_tracking_id

      message = {
        tracking_id: tracking_id,
        reason: :REASON_CONTENT_SAFETY,
        revocation_date: Google::Protobuf::Timestamp.new(seconds: Time.now.to_i, nanos: 0),
      }

      ActiveRecord.after_all_transactions_commit do
        GitHub.hydro_kv_gc_cus_02_publisher.publish(
          message,
          schema: HYDRO_SCHEMA_TOKEN_REVOCATION,
          partition_key: tracking_id,
        )
      end
    end

    private_class_method(
      :publish_monitoring_state_change_event,
      :publish_token_revocation_event,
    )
  end
end
