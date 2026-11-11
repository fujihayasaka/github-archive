# typed: strict
# frozen_string_literal: true

require "google/protobuf/timestamp_pb"
require "monolith-twirp-copilot-content_safety"

module CopilotContentSafety
  class MonitoringState
    sig do
      params(
        user: ::User,
        monitoring_state: T.untyped,
        client_name: T.nilable(String),
        reason: String,
        chat_turn_scan_event_id: T.nilable(String),
      ).returns(GitHub::Result)
    end
    def self.set_from_twirp!(
      user:,
      monitoring_state:,
      client_name:,
      reason: "",
      chat_turn_scan_event_id: nil
    )
      result = monitored_request_value(monitoring_state)
      return result unless result.ok?

      initiator_type = initiator_type_for_client(client_name)

      GitHub::Result.new do
        updated_at = MonitoredUser.set_monitoring_state!(
          user: user,
          monitored: result.value!,
          initiator_type: initiator_type,
          reason: reason,
          chat_turn_scan_event_id: chat_turn_scan_event_id,
        )

        {
          updated_at: twirp_timestamp(updated_at),
        }
      end
    end

    sig { params(user: ::User).returns(T::Hash[Symbol, T.untyped]) }
    def self.to_twirp(user:)
      {
        monitoring_state: twirp_monitoring_state(MonitoredUser.monitored?(user)),
      }
    end

    sig { params(user: ::User).returns(T::Boolean) }
    def self.monitored?(user)
      MonitoredUser.monitored?(user)
    end

    sig { params(monitoring_state: T.untyped).returns(GitHub::Result) }
    def self.monitored_request_value(monitoring_state)
      case monitoring_state
      when MonolithTwirp::Copilot::ContentSafety::V1::MonitoringState::MONITORING_STATE_MONITORED,
        :MONITORING_STATE_MONITORED
        GitHub::Result.new { true }
      when MonolithTwirp::Copilot::ContentSafety::V1::MonitoringState::MONITORING_STATE_NOT_MONITORED,
        :MONITORING_STATE_NOT_MONITORED
        GitHub::Result.new { false }
      else
        GitHub::Result.error(Twirp::Error.invalid_argument(
          "must be MONITORING_STATE_MONITORED or MONITORING_STATE_NOT_MONITORED",
          argument: "monitoring_state",
        ))
      end
    end

    sig { params(client_name: T.nilable(String)).returns(Symbol) }
    def self.initiator_type_for_client(client_name)
      case client_name
      when "copilot_api"
        :CAPI
      else
        :INITIATOR_TYPE_UNKNOWN
      end
    end

    sig { params(monitored: T::Boolean).returns(T.untyped) }
    def self.twirp_monitoring_state(monitored)
      if monitored
        MonolithTwirp::Copilot::ContentSafety::V1::MonitoringState::MONITORING_STATE_MONITORED
      else
        MonolithTwirp::Copilot::ContentSafety::V1::MonitoringState::MONITORING_STATE_NOT_MONITORED
      end
    end

    sig { params(time: Time).returns(Google::Protobuf::Timestamp) }
    def self.twirp_timestamp(time)
      Google::Protobuf::Timestamp.new(seconds: time.to_i, nanos: 0)
    end

    private_class_method(
      :monitored_request_value,
      :initiator_type_for_client,
      :twirp_monitoring_state,
      :twirp_timestamp,
    )
  end
end
